import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    // iOS 18 Glass Design Update
    var server: MJPEGServer?
    let context = CIContext()
    
    @Published var isRunning = false
    @Published var currentResolutionString = "1920x1080"
    @Published var currentFPS: Int = 30
    
    @Published var currentLens: String = "back"
    @Published var isFlashlightOn: Bool = false {
        didSet {
            updateFlashlight()
        }
    }
    
    private func getCurrentDevice() -> AVCaptureDevice? {
        switch currentLens {
        case "front":
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        case "telephoto":
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case "ultrawide":
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        default:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
    }
    
    private func updateFlashlight() {
        if let device = getCurrentDevice(), device.hasTorch {
            do {
                try device.lockForConfiguration()
                if isFlashlightOn {
                    try device.setTorchModeOn(level: 1.0)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    @Published var exposureValue: Float = 0.0 {
        didSet {
            if let device = getCurrentDevice() {
                do {
                    try device.lockForConfiguration()
                    let clamped = min(max(exposureValue, device.minExposureTargetBias), device.maxExposureTargetBias)
                    device.setExposureTargetBias(clamped, completionHandler: nil)
                    device.unlockForConfiguration()
                } catch { }
            }
        }
    }
    @Published var zoomFactor: CGFloat = 1.0 {
        didSet {
            if let device = getCurrentDevice() {
                do {
                    try device.lockForConfiguration()
                    let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
                    let clamped = min(max(zoomFactor, 1.0), maxZoom)
                    device.videoZoomFactor = clamped
                    device.unlockForConfiguration()
                } catch { }
            }
        }
    }
    
    @Published var port: Int = 8080 {
        didSet {
            if isRunning {
                // Restart server with new port
                server?.listener?.cancel()
                server = MJPEGServer(port: UInt16(port))
                server?.onSettingsUpdate = { [weak self] res, fps, lens, flash in
                    self?.updateSettings(resolution: res ?? self?.currentResolutionString ?? "1920x1080", 
                                         fps: fps ?? self?.currentFPS ?? 30,
                                         lens: lens ?? self?.currentLens ?? "back",
                                         flash: flash ?? self?.isFlashlightOn ?? false)
                }
            }
        }
    }
    
    override init() {
        super.init()
        server = MJPEGServer(port: UInt16(port))
        
        server?.onSettingsUpdate = { [weak self] res, fps, lens, flash in
            self?.updateSettings(resolution: res ?? self?.currentResolutionString ?? "1920x1080", 
                                 fps: fps ?? self?.currentFPS ?? 30,
                                 lens: lens ?? self?.currentLens ?? "back",
                                 flash: flash ?? self?.isFlashlightOn ?? false)
        }
        
        setupCamera()
    }
    
    func updateSettings(resolution: String, fps: Int, lens: String, flash: Bool) {
        var changed = false
        if self.currentResolutionString != resolution { self.currentResolutionString = resolution; changed = true }
        if self.currentFPS != fps { self.currentFPS = fps; changed = true }
        if self.currentLens != lens { self.currentLens = lens; changed = true }
        if self.isFlashlightOn != flash { self.isFlashlightOn = flash } // No need to reconfig session just for flash
        
        if changed {
            if self.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.applyCameraConfiguration()
                }
            } else {
                self.applyCameraConfiguration()
            }
        }
    }
    
    private func applyCameraConfiguration() {
        if let device = getCurrentDevice() {
            
            var targetWidth: Int32 = 1920
            switch currentResolutionString {
            case "3840x2160": targetWidth = 3840
            case "1920x1080": targetWidth = 1920
            case "1280x720": targetWidth = 1280
            case "640x480": targetWidth = 640
            default: targetWidth = 1920
            }
            
            var bestFormat: AVCaptureDevice.Format?
            var fallbackFormat: AVCaptureDevice.Format?
            
            for format in device.formats {
                let desc = format.formatDescription
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                if dims.width == targetWidth {
                    if fallbackFormat == nil { fallbackFormat = format }
                    for range in format.videoSupportedFrameRateRanges {
                        if Float64(currentFPS) >= range.minFrameRate && Float64(currentFPS) <= range.maxFrameRate {
                            bestFormat = format
                            break
                        }
                    }
                }
                if bestFormat != nil { break }
            }
            
            session.beginConfiguration()
            session.sessionPreset = .inputPriority
            
            // Switch inputs if device changed
            for input in session.inputs {
                session.removeInput(input)
            }
            if let newInput = try? AVCaptureDeviceInput(device: device) {
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                }
            }
            
            do {
                try device.lockForConfiguration()
                if let format = bestFormat ?? fallbackFormat {
                    device.activeFormat = format
                }
                
                var safeFPS = currentFPS
                var isValid = false
                for range in device.activeFormat.videoSupportedFrameRateRanges {
                    if Float64(currentFPS) >= range.minFrameRate && Float64(currentFPS) <= range.maxFrameRate {
                        isValid = true
                        break
                    }
                }
                if !isValid {
                    safeFPS = Int(device.activeFormat.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30.0)
                }
                
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(safeFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(safeFPS))
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.currentFPS = safeFPS
                }
            } catch {
                print("Could not configure device framerate")
            }
            
            if let output = session.outputs.first as? AVCaptureVideoDataOutput,
               let connection = output.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) { // Landscape Right
                        connection.videoRotationAngle = 90
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .landscapeRight
                    }
                }
                
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (self.currentLens == "front")
                }
            }
            
            session.commitConfiguration()
        }
    }
    
    func setupCamera() {
        session.beginConfiguration()
        
        if let device = getCurrentDevice(),
           let input = try? AVCaptureDeviceInput(device: device) {
            if session.canAddInput(input) {
                session.addInput(input)
            }
        }
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.alwaysDiscardsLateVideoFrames = true
        
        let queue = DispatchQueue(label: "camera.queue", qos: .userInteractive)
        output.setSampleBufferDelegate(self, queue: queue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        if let connection = output.connection(with: .video) {
            // FORCE LandscapeRight for the MJPEG stream
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            } else {
                connection.videoOrientation = .landscapeRight
            }
        }
        
        session.commitConfiguration()
        applyCameraConfiguration()
    }
    
    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.applyCameraConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.isRunning = true }
        }
    }
    
    func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let uiImage = UIImage(cgImage: cgImage)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.6) {
            server?.sendFrame(jpegData)
        }
    }
}

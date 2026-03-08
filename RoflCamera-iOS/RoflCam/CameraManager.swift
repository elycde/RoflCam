import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var server: MJPEGServer?
    let context = CIContext()
    
    @Published var isRunning = false
    @Published var currentResolutionString = "1920x1080"
    @Published var currentFPS: Int = 30
    
    @Published var exposureValue: Float = 0.0 {
        didSet {
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
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
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
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
                server?.onSettingsUpdate = { [weak self] res, fps in
                    self?.updateSettings(resolution: res, fps: fps)
                }
            }
        }
    }
    
    override init() {
        super.init()
        server = MJPEGServer(port: UInt16(port))
        
        server?.onSettingsUpdate = { [weak self] res, fps in
            self?.updateSettings(resolution: res, fps: fps)
        }
        
        setupCamera()
    }
    
    func updateSettings(resolution: String, fps: Int) {
        if self.currentResolutionString != resolution || self.currentFPS != fps {
            self.currentResolutionString = resolution
            self.currentFPS = fps
            
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
        session.beginConfiguration()
        
        switch currentResolutionString {
        case "3840x2160": session.sessionPreset = .hd4K3840x2160
        case "1920x1080": session.sessionPreset = .hd1920x1080
        case "1280x720": session.sessionPreset = .hd1280x720
        case "640x480": session.sessionPreset = .vga640x480
        default: session.sessionPreset = .hd1920x1080
        }
        
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(currentFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(currentFPS))
                device.unlockForConfiguration()
            } catch {
                print("Could not configure device framerate")
            }
        }
        
        session.commitConfiguration()
    }
    
    func setupCamera() {
        session.beginConfiguration()
        
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
            connection.videoOrientation = .landscapeRight
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

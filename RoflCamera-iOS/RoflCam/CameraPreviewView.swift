import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        // Initialize with portrait but we will handle logic
        previewLayer.connection?.videoOrientation = .portrait
        
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
                
                // Adjust for rotation
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    let interfaceOrientation = windowScene.interfaceOrientation
                    
                    if #available(iOS 17.0, *) {
                        let angle: Double = {
                            switch interfaceOrientation {
                            case .landscapeLeft: return 180
                            case .landscapeRight: return 0
                            case .portraitUpsideDown: return 270
                            default: return 90 // portrait
                            }
                        }()
                        previewLayer.connection?.videoRotationAngle = angle
                    } else {
                        switch interfaceOrientation {
                        case .landscapeLeft:
                            previewLayer.connection?.videoOrientation = .landscapeLeft
                        case .landscapeRight:
                            previewLayer.connection?.videoOrientation = .landscapeRight
                        case .portraitUpsideDown:
                            previewLayer.connection?.videoOrientation = .portraitUpsideDown
                        default:
                            previewLayer.connection?.videoOrientation = .portrait
                        }
                    }
                }
            }
        }
    }
}

import Foundation
import Network
import UIKit

class MJPEGServer {
    var listener: NWListener?
    var connections: [NWConnection] = []
    let queue = DispatchQueue(label: "mjpeg.server")
    
    var onSettingsUpdate: ((String?, Int?, String?, Bool?) -> Void)?
    
    init(port: UInt16) {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
            
            // Set up Bonjour auto-discovery
            let serviceName = "RoflCam-\(UIDevice.current.name)-\(port)"
            listener?.service = NWListener.Service(name: serviceName, type: "_roflcam._tcp")
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener?.start(queue: queue)
        } catch {
            print("Failed to start listener: \(error)")
        }
    }
    
    func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, isComplete, error in
            guard let self = self, let content = content, let requestStr = String(data: content, encoding: .utf8) else { return }
            
            let lines = requestStr.components(separatedBy: "\n")
            guard let firstLine = lines.first else { return }
            let components = firstLine.components(separatedBy: " ")
            guard components.count >= 2 else { return }
            
            let path = components[1]
            if path == "/ping" {
                let response = "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nROFLCAM_OK"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if path.hasPrefix("/settings?") {
                self.processSettingsQuery(path: path)
                let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\nOK"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            
            let header = """
            HTTP/1.1 200 OK\r
            Access-Control-Allow-Origin: *\r
            Connection: close\r
            Cache-Control: private, no-cache, no-store, must-revalidate\r
            Content-Type: multipart/x-mixed-replace; boundary=roflcam\r
            \r\n
            """
            connection.send(content: header.data(using: .utf8), completion: .contentProcessed { error in
                if error == nil {
                    self.queue.async { self.connections.append(connection) }
                }
            })
        }
    }
    
    private func processSettingsQuery(path: String) {
        guard let url = URL(string: "http://localhost\(path)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }
        
        var newRes: String?
        var newFps: Int?
        var newLens: String?
        var newFlash: Bool?
        
        for item in queryItems {
            if item.name == "res", let value = item.value {
                newRes = value
            } else if item.name == "fps", let value = item.value {
                newFps = Int(value)
            } else if item.name == "lens", let value = item.value {
                newLens = value
            } else if item.name == "flash", let value = item.value {
                newFlash = (value == "1" || value == "true")
            }
        }
        
        DispatchQueue.main.async {
            self.onSettingsUpdate?(newRes, newFps, newLens, newFlash)
        }
    }
    
    func sendFrame(_ data: Data) {
        let header = """
        --roflcam\r
        Content-Type: image/jpeg\r
        Content-Length: \(data.count)\r
        \r\n
        """
        let footer = "\r\n"
        
        var fullData = header.data(using: .utf8)!
        fullData.append(data)
        fullData.append(footer.data(using: .utf8)!)
        
        queue.async {
            for connection in self.connections {
                if connection.state == .ready {
                    connection.send(content: fullData, completion: .contentProcessed { _ in })
                }
            }
            self.connections.removeAll { conn in
                switch conn.state {
                case .cancelled, .failed: return true
                default: return false
                }
            }
        }
    }
}

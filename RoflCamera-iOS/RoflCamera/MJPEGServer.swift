import Foundation
import Network

class MJPEGServer {
    var listener: NWListener?
    var connections: [NWConnection] = []
    let queue = DispatchQueue(label: "mjpeg.server")
    
    init(port: UInt16) {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
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
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { content, _, isComplete, error in
            if content != nil {
                let header = """
                HTTP/1.1 200 OK\r
                Access-Control-Allow-Origin: *\r
                Connection: close\r
                Cache-Control: private, no-cache, no-store, must-revalidate\r
                Content-Type: multipart/x-mixed-replace; boundary=roflcam\r
                \r
                
                """
                connection.send(content: header.data(using: .utf8), completion: .contentProcessed { error in
                    if error == nil {
                        self.queue.async { self.connections.append(connection) }
                    }
                })
            }
        }
    }
    
    func sendFrame(_ data: Data) {
        let header = """
        --roflcam\r
        Content-Type: image/jpeg\r
        Content-Length: \(data.count)\r
        \r
        
        """
        let footer = "\r\n"
        
        var fullData = header.data(using: .utf8)!
        fullData.append(data)
        fullData.append(footer.data(using: .utf8)!)
        
        queue.async {
            for connection in self.connections {
                if connection.state == .ready {
                    connection.send(content: fullData, completion: .contentProcessed { error in
                        // error handled silently
                    })
                }
            }
            self.connections.removeAll { $0.state == .cancelled || $0.state == .failed }
        }
    }
}

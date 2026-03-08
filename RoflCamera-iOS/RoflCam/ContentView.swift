import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var serverIPs: [String] = []
    @State private var isScreenBlackedOut = false
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var autoBlackoutTimer: Timer?
    @State private var portString: String = "8080"
    
    let resolutions = ["3840x2160", "1920x1080", "1280x720", "640x480"]
    let fpsList = [30, 60, 120]
    
    var body: some View {
        ZStack {
            // Live background camera preview
            CameraPreviewView(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)
                
            if isScreenBlackedOut {
                Color.black.edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        wakeScreen()
                    }
            } else {
                VStack {
                    // Top Bar (Native Camera Style)
                    HStack {
                        if cameraManager.isRunning {
                            HStack {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text("LIVE")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                            
                            Spacer()
                            
                            if let firstIP = serverIPs.first {
                                Text("\\(firstIP):\\(portString)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(10)
                            }
                        } else {
                            Text("RoflCam")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 5) {
                                Text("ПОРТ:")
                                    .font(.caption).bold().foregroundColor(.white)
                                TextField("8080", text: $portString)
                                    .keyboardType(.numberPad)
                                    .foregroundColor(.yellow)
                                    .frame(width: 50)
                                    .onChange(of: portString) { newValue in
                                        if let newPort = Int(newValue) {
                                            cameraManager.port = newPort
                                            updateIPs()
                                        }
                                    }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Bottom Controls (Native Camera Style)
                    VStack(spacing: 0) {
                        // Settings row (Resolution & FPS)
                        if !cameraManager.isRunning {
                            HStack(spacing: 20) {
                                Menu {
                                    ForEach(resolutions, id: \\.self) { res in
                                        Button(res) { cameraManager.currentResolutionString = res }
                                    }
                                } label: {
                                    Text(cameraManager.currentResolutionString)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.yellow)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Capsule())
                                }

                                Menu {
                                    ForEach(fpsList, id: \\.self) { fps in
                                        Button("\\(fps) FPS") { cameraManager.currentFPS = fps }
                                    }
                                } label: {
                                    Text("\\(cameraManager.currentFPS) FPS")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.yellow)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        
                        // Action row (Shutter Button / Action Buttons)
                        HStack {
                            if cameraManager.isRunning {
                                Button(action: blackoutScreen) {
                                    Image(systemName: "moon.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 60, height: 60)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    cameraManager.stop()
                                }) {
                                    // Stop recording square inside circle
                                    ZStack {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 4)
                                            .frame(width: 70, height: 70)
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.red)
                                            .frame(width: 30, height: 30)
                                    }
                                }
                                
                                Spacer()
                                
                                // Placeholder to center the middle button perfectly
                                Color.clear.frame(width: 60, height: 60)
                                
                            } else {
                                Spacer()
                                
                                Button(action: {
                                    if let p = Int(portString) { cameraManager.port = p }
                                    cameraManager.start()
                                    updateIPs()
                                    startAutoBlackoutTimer()
                                }) {
                                    // Start recording red circle
                                    ZStack {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 4)
                                            .frame(width: 70, height: 70)
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 58, height: 58)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 40)
                    }
                    .background(
                        LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                            .edgesIgnoringSafeArea(.bottom)
                    )
                }
                .onTapGesture {
                    resetAutoBlackoutTimer()
                }
            }
        }
        .statusBarHidden(isScreenBlackedOut)
        .onAppear {
            portString = String(cameraManager.port)
            UIApplication.shared.isIdleTimerDisabled = true
            updateIPs()
            cameraManager.setupCamera()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            cameraManager.stop()
            autoBlackoutTimer?.invalidate()
            UIScreen.main.brightness = previousBrightness
        }
    }
    
    // ... [rest of the methods: updateIPs, blackoutScreen, wakeScreen, startAutoBlackoutTimer, resetAutoBlackoutTimer] retained as before ...
    func updateIPs() {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        guard let firstAddr = ifaddr else { return }
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let address = String(cString: hostname)
                    if !address.hasPrefix("fe80") {
                        addresses.append(address)
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        serverIPs = addresses
    }
    
    func blackoutScreen() {
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.0
        isScreenBlackedOut = true
        autoBlackoutTimer?.invalidate()
    }
    
    func wakeScreen() {
        UIScreen.main.brightness = previousBrightness
        isScreenBlackedOut = false
        resetAutoBlackoutTimer()
    }
    
    func startAutoBlackoutTimer() {
        autoBlackoutTimer?.invalidate()
        autoBlackoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            if cameraManager.isRunning {
                blackoutScreen()
            }
        }
    }
    
    func resetAutoBlackoutTimer() {
        if cameraManager.isRunning {
            startAutoBlackoutTimer()
        }
    }
}

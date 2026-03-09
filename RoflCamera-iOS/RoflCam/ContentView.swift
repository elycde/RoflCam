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
                        // Top Bar (Premium Glass Style)
                        HStack {
                            if cameraManager.isRunning {
                                HStack {
                                    Circle().fill(Color.red).frame(width: 8, height: 8)
                                    Text("LIVE")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .glassBackgroundEffect()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                Spacer()
                                
                                if let firstIP = serverIPs.first {
                                    Text("\(firstIP):\(portString)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(.ultraThinMaterial)
                                        .glassBackgroundEffect()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            } else {
                                Text("RoflCam Pro")
                                    .font(.system(.title3, design: .rounded).bold())
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("PORT:")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                    TextField("8080", text: $portString)
                                        .keyboardType(.numberPad)
                                        .foregroundColor(.yellow)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 50)
                                        .onChange(of: portString) { newValue in
                                            if let newPort = Int(newValue) {
                                                cameraManager.port = newPort
                                                updateIPs()
                                            }
                                        }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .glassBackgroundEffect()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                        
                        Spacer()
                        
                        // Bottom Controls
                        VStack(spacing: 16) {
                            // Settings row (Glass Capsules)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    Menu {
                                        ForEach(["back", "ultrawide", "telephoto", "front"], id: \.self) { lens in
                                            Button(lens.capitalized) { cameraManager.currentLens = lens }
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "camera.fill")
                                            Text(cameraManager.currentLens == "ultrawide" ? "UW" : cameraManager.currentLens.capitalized)
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(cameraManager.currentLens == "front" ? .blue : .yellow)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(.ultraThinMaterial)
                                        .glassBackgroundEffect()
                                        .clipShape(Capsule())
                                    }

                                    Menu {
                                        ForEach(resolutions, id: \.self) { res in
                                            Button(res) { cameraManager.currentResolutionString = res }
                                        }
                                    } label: {
                                        Text(cameraManager.currentResolutionString)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .glassBackgroundEffect()
                                            .clipShape(Capsule())
                                    }

                                    Menu {
                                        ForEach(fpsList, id: \.self) { fps in
                                            Button("\(fps) FPS") { cameraManager.currentFPS = fps }
                                        }
                                    } label: {
                                        Text("\(cameraManager.currentFPS) FPS")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .glassBackgroundEffect()
                                            .clipShape(Capsule())
                                    }
                                    
                                    Button(action: {
                                        cameraManager.isFlashlightOn.toggle()
                                    }) {
                                        Image(systemName: cameraManager.isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(cameraManager.isFlashlightOn ? .white : .yellow)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(cameraManager.isFlashlightOn ? Color.yellow.opacity(0.8) : Color.clear)
                                            .background(.ultraThinMaterial)
                                            .glassBackgroundEffect()
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Sliders
                            VStack(spacing: 12) {
                                HStack(spacing: 15) {
                                    Image(systemName: "plus.magnifyingglass")
                                        .foregroundColor(.white.opacity(0.7))
                                    Slider(value: $cameraManager.zoomFactor, in: 1.0...10.0, step: 0.1)
                                        .accentColor(.yellow)
                                }
                                HStack(spacing: 15) {
                                    Image(systemName: "sun.max.fill")
                                        .foregroundColor(.white.opacity(0.7))
                                    Slider(value: $cameraManager.exposureValue, in: -8.0...8.0, step: 0.5)
                                        .accentColor(.yellow)
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 20)
                            .background(.ultraThinMaterial)
                            .glassBackgroundEffect()
                            .clipShape(RoundedRectangle(cornerRadius: 30))
                            .padding(.horizontal, 20)
                            
                            // Action Buttons
                            HStack(spacing: 40) {
                                if cameraManager.isRunning {
                                    Button(action: blackoutScreen) {
                                        ZStack {
                                            Circle().fill(.ultraThinMaterial).glassBackgroundEffect()
                                            Image(systemName: "moon.stars.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                        }
                                        .frame(width: 60, height: 60)
                                    }
                                    
                                    Button(action: {
                                        cameraManager.stop()
                                    }) {
                                        ZStack {
                                            Circle().fill(.white).frame(width: 80, height: 80)
                                            Circle().fill(.black).frame(width: 72, height: 72)
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.red)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                    
                                    // Placeholder
                                    Color.clear.frame(width: 60, height: 60)
                                    
                                } else {
                                    Button(action: {
                                        if let p = Int(portString) { cameraManager.port = p }
                                        cameraManager.start()
                                        updateIPs()
                                        startAutoBlackoutTimer()
                                    }) {
                                        ZStack {
                                            Circle().fill(.white).frame(width: 80, height: 80)
                                            Circle().fill(.black).frame(width: 72, height: 72)
                                            Circle().fill(.red).frame(width: 60, height: 60)
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 50)
                        }
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

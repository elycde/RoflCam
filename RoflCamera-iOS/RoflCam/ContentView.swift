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
                // UI Geometry Stabilizer
                GeometryReader { geo in
                    VStack {
                        // Top Bar (Liquid Glass Pro)
                        HStack {
                            if cameraManager.isRunning {
                                HStack(spacing: 8) {
                                    Circle().fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .shadow(color: .red, radius: 6)
                                    Text("LIVE")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .glassEffect()
                                
                                Spacer()
                                
                                if let firstIP = serverIPs.first {
                                    Text("\(firstIP):\(portString)")
                                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .glassEffect()
                                }
                            } else {
                                Text("RoflCam")
                                    .font(.system(.title2, design: .rounded).weight(.heavy))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 10)
                                    
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Text("PORT")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                    TextField("8080", text: $portString)
                                        .keyboardType(.numberPad)
                                        .foregroundColor(.yellow)
                                        .font(.system(.body, design: .monospaced).weight(.bold))
                                        .frame(width: 50)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .glassEffect()
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        // Main Control Surface
                        VStack(spacing: 25) {
                            // Floating Lens & FPS Bar
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    Menu {
                                        ForEach(["back", "ultrawide", "telephoto", "front"], id: \.self) { lens in
                                            Button(lens.capitalized) { cameraManager.currentLens = lens }
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "camera.filters")
                                            Text(cameraManager.currentLens.capitalized)
                                        }
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundColor(cameraManager.currentLens == "front" ? .cyan : .yellow)
                                        .padding(.horizontal, 18).padding(.vertical, 14)
                                        .glassEffect()
                                    }

                                    Menu {
                                        ForEach(resolutions, id: \.self) { res in
                                            Button(res) { cameraManager.currentResolutionString = res }
                                        }
                                    } label: {
                                        Text(cameraManager.currentResolutionString)
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 18).padding(.vertical, 14)
                                            .glassEffect()
                                    }

                                    Menu {
                                        ForEach(fpsList, id: \.self) { fps in
                                            Button("\(fps) FPS") { cameraManager.currentFPS = fps }
                                        }
                                    } label: {
                                        Text("\(cameraManager.currentFPS) FPS")
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 18).padding(.vertical, 14)
                                            .glassEffect()
                                    }
                                }
                                .padding(.horizontal, 30)
                            }
                            
                            // Interactive Liquid Sliders
                            VStack(spacing: 20) {
                                ControlSliderGeneric(icon: "magnifyingglass", value: $cameraManager.zoomFactor, range: 1.0...10.0)
                                ControlSliderGeneric(icon: "sun.max.fill", value: $cameraManager.exposureValue, range: -8.0...8.0)
                            }
                            .padding(25)
                            .glassEffect()
                            .padding(.horizontal, 30)
                            
                            // Liquid Action Group
                            HStack(spacing: 40) {
                                if cameraManager.isRunning {
                                    ControlButton(icon: "moon.fill", active: false) { blackoutScreen() }
                                    
                                    Button(action: { cameraManager.stop() }) {
                                        ZStack {
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .frame(width: 85, height: 85)
                                                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                                            
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.red)
                                                .frame(width: 32, height: 32)
                                                .shadow(color: .red.opacity(0.4), radius: 10)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    ControlButton(icon: cameraManager.isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill", 
                                                 active: cameraManager.isFlashlightOn) {
                                        cameraManager.isFlashlightOn.toggle()
                                    }
                                    
                                } else {
                                    Button(action: {
                                        if let p = Int(portString) { cameraManager.port = p }
                                        cameraManager.start()
                                        updateIPs()
                                        startAutoBlackoutTimer()
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .frame(width: 100, height: 100)
                                                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                                            
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 75, height: 75)
                                                .shadow(color: .red.opacity(0.6), radius: 25)
                                                .overlay(
                                                    Circle()
                                                        .stroke(.white.opacity(0.4), lineWidth: 0.5)
                                                        .padding(2)
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 60)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .onTapGesture {
                    resetAutoBlackoutTimer()
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

// MARK: - Liquid Components
struct ControlSliderGeneric<T: BinaryFloatingPoint>: View where T.Stride: Float80 {
    let icon: String
    @Binding var value: T
    var range: ClosedRange<T>
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            Slider(value: $value, in: range)
                .tint(.yellow)
        }
    }
}

struct ControlButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(active ? .yellow : .white)
                .frame(width: 70, height: 70)
                .background(active ? Color.yellow.opacity(0.15) : Color.clear)
                .glassEffect()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid Glass Bridge (iOS 18 Native Mesh & Materials)
struct LiquidGlassModifier: ViewModifier {
    var material: Material
    var shape: AnyShape
    
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Liquid: Native iOS 18 MeshGradient for the 'moving liquid' feel
                    if #available(iOS 18.0, *) {
                        MeshGradient(width: 3, height: 3, points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.5], [0.5, 0.5], [1, 0.5],
                            [0, 1], [0.5, 1], [1, 1]
                        ], colors: [
                            .black.opacity(0.2), .black.opacity(0.1), .black.opacity(0.2),
                            .white.opacity(0.05), .clear, .white.opacity(0.05),
                            .black.opacity(0.2), .black.opacity(0.1), .black.opacity(0.2)
                        ])
                        .blur(radius: 20)
                    }
                    
                    // Glass: Native iOS 18 Material
                    shape.fill(.ultraThinMaterial)
                }
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 10)
    }
}

extension View {
    func glassEffect(_ material: Material = .thin, in shape: some Shape = RoundedRectangle(cornerRadius: 24, style: .continuous)) -> some View {
        self.modifier(LiquidGlassModifier(material: material, shape: AnyShape(shape)))
    }
}

struct GlassEffectContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack { content }
    }
}

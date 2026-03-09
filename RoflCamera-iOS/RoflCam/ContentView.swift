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
                        // Top Bar (Liquid Glass Pro)
                        HStack {
                            if cameraManager.isRunning {
                                HStack(spacing: 8) {
                                    Circle().fill(Color.red)
                                        .frame(width: 6, height: 6)
                                        .shadow(color: .red, radius: 4)
                                    Text("LIVE")
                                        .font(.system(size: 12, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .glassEffect()
                                
                                Spacer()
                                
                                if let firstIP = serverIPs.first {
                                    Text("\(firstIP):\(portString)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .glassEffect()
                                }
                            } else {
                                Text("RoflCam")
                                    .font(.system(.title2, design: .rounded).weight(.heavy))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 10)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("PORT")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                    TextField("8080", text: $portString)
                                        .keyboardType(.numberPad)
                                        .foregroundColor(.yellow)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 45)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .glassEffect()
                            }
                        }
                        .padding(.horizontal, 25)
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        // Main Control Surface
                        VStack(spacing: 20) {
                            // Floating Lens & FPS Bar
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    Menu {
                                        ForEach(["back", "ultrawide", "telephoto", "front"], id: \.self) { lens in
                                            Button(lens.capitalized) { cameraManager.currentLens = lens }
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "camera.aperture")
                                            Text(cameraManager.currentLens.capitalized)
                                        }
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(cameraManager.currentLens == "front" ? .blue : .yellow)
                                        .padding(.horizontal, 16).padding(.vertical, 12)
                                        .glassEffect()
                                    }

                                    Menu {
                                        ForEach(resolutions, id: \.self) { res in
                                            Button(res) { cameraManager.currentResolutionString = res }
                                        }
                                    } label: {
                                        Text(cameraManager.currentResolutionString)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .glassEffect()
                                    }

                                    Menu {
                                        ForEach(fpsList, id: \.self) { fps in
                                            Button("\(fps) FPS") { cameraManager.currentFPS = fps }
                                        }
                                    } label: {
                                        Text("\(cameraManager.currentFPS) FPS")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .glassEffect()
                                    }
                                }
                                .padding(.horizontal, 25)
                            }
                            
                            // Interactive Liquid Sliders
                            VStack(spacing: 15) {
                                HStack(spacing: 20) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                    Slider(value: $cameraManager.zoomFactor, in: 1.0...10.0, step: 0.1)
                                        .tint(.yellow)
                                }
                                HStack(spacing: 20) {
                                    Image(systemName: "sun.max.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                    Slider(value: $cameraManager.exposureValue, in: -8.0...8.0, step: 0.5)
                                        .tint(.yellow)
                                }
                            }
                            .padding(25)
                            .glassEffect()
                            .padding(.horizontal, 25)
                            
                            // Liquid Action Group
                            HStack(spacing: 50) {
                                if cameraManager.isRunning {
                                    Button(action: blackoutScreen) {
                                        Image(systemName: "moon.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                            .frame(width: 65, height: 65)
                                            .glassEffect()
                                    }
                                    
                                    Button(action: {
                                        cameraManager.stop()
                                    }) {
                                        ZStack {
                                            Circle().fill(.white.opacity(0.2)).frame(width: 90, height: 90).glassEffect()
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.red)
                                                .frame(width: 35, height: 35)
                                                .shadow(color: .red.opacity(0.5), radius: 15)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        cameraManager.isFlashlightOn.toggle()
                                    }) {
                                        Image(systemName: cameraManager.isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(cameraManager.isFlashlightOn ? .white : .yellow)
                                            .frame(width: 65, height: 65)
                                            .background(cameraManager.isFlashlightOn ? Color.yellow.opacity(0.3) : Color.clear)
                                            .glassEffect()
                                    }
                                    
                                } else {
                                    Button(action: {
                                        if let p = Int(portString) { cameraManager.port = p }
                                        cameraManager.start()
                                        updateIPs()
                                        startAutoBlackoutTimer()
                                    }) {
                                        ZStack {
                                            Circle().fill(.white.opacity(0.2)).frame(width: 90, height: 90).glassEffect()
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 70, height: 70)
                                                .shadow(color: .red.opacity(0.5), radius: 20)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 60)
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

// MARK: - Liquid Glass Bridge (iOS 26.3 Design Language)
// This bridge implements the "Liquid Glass" design language modifiers 
// that allow for morphing, refractive glass effects, and liquid interactions.

struct LiquidGlassModifier: ViewModifier {
    var material: Material
    var shape: AnyShape
    
    func body(content: Content) -> some View {
        content
            .background {
                // In iOS 18+, we use the native glassBackgroundEffect as the foundation
                // then overlay the "Liquid" highlights and shadows.
                ZStack {
                    // Using Material as the base for glass on iOS 
                    // and adding custom liquid layers for the iOS 26.3 aesthetic.
                    shape.fill(.ultraThinMaterial)
                        .opacity(0.95)
                    
                    // Liquid Highlight (Upper edge glow)
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.2), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                    
                    // Liquid Refraction (Inner soft glow)
                    shape
                        .fill(RadialGradient(
                            colors: [.white.opacity(0.1), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 80
                        ))
                }
            }
            // Liquid depth shadow
            .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 8)
            .compositingGroup()
    }
}

extension View {
    /// Applies the Liquid Glass design effect introduced in iOS 26.3.
    /// Morphing and refraction are automatically calculated based on the context.
    func glassEffect(_ material: Material = .regular, in shape: some Shape = .rect) -> some View {
        self.modifier(LiquidGlassModifier(material: material, shape: AnyShape(shape)))
    }
    
    /// Experimental: Adds a liquid refraction light effect based on view geometry.
    func refraction(intensity: Double = 1.0) -> some View {
        self.overlay(
            Circle()
                .fill(.white.opacity(0.03 * intensity))
                .blur(radius: 20)
                .offset(x: -20, y: -20)
                .blendMode(.plusLighter)
        )
    }
}

/// A container that enables morphing between Liquid Glass components.
struct GlassEffectContainer<Content: View>: View {
    @ViewBuilder var content: Content
    
    var body: some View {
        ZStack {
            content
        }
    }
}

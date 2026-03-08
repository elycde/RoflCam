import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var serverIPs: [String] = []
    @State private var isScreenBlackedOut = false
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var autoBlackoutTimer: Timer?
    
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
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Text("RoflCam")
                            .font(.largeTitle)
                            .bold()
                            .foregroundColor(.white)
                        
                        if cameraManager.isRunning {
                            Text("Камера активна 🎥")
                                .foregroundColor(.green)
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Wi-Fi IP:")
                                    .bold()
                                    .foregroundColor(.white)
                                if serverIPs.isEmpty {
                                    Text("Получение IP...")
                                        .foregroundColor(.gray)
                                } else {
                                    ForEach(serverIPs, id: \.self) { ip in
                                        Text("\(ip):\(cameraManager.port)")
                                            .foregroundColor(.white)
                                    }
                                }
                                
                                Text("Параметры трансляции:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 10)
                                Text("\(cameraManager.currentResolutionString) @ \(cameraManager.currentFPS) FPS")
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(10)
                            
                            Button(action: {
                                blackoutScreen()
                            }) {
                                Text("Спящий режим (сохранить АКБ)")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                cameraManager.stop()
                            }) {
                                Text("Остановить")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red)
                                    .cornerRadius(10)
                            }
                            
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Text("Порт:")
                                        .foregroundColor(.white)
                                    Spacer()
                                    TextField("8080", value: $cameraManager.port, formatter: NumberFormatter())
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundColor(.white)
                                }
                                
                                HStack {
                                    Text("Разрешение:")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Разрешение", selection: $cameraManager.currentResolutionString) {
                                        ForEach(resolutions, id: \.self) { res in
                                            Text(res).tag(res)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                                
                                HStack {
                                    Text("FPS:")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Picker("Частота кадров", selection: $cameraManager.currentFPS) {
                                        ForEach(fpsList, id: \.self) { fps in
                                            Text("\(fps) FPS").tag(fps)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            }
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(10)
                            
                            Button(action: {
                                cameraManager.start()
                                updateIPs()
                                startAutoBlackoutTimer()
                            }) {
                                Text("Начать трансляцию")
                                    .foregroundColor(.white)
                                    .bold()
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.green)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    // Liquidglass / Glassmorphism effect overlay for bottom controls
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding()
                }
                .onTapGesture {
                    resetAutoBlackoutTimer()
                }
            }
        }
        .statusBarHidden(isScreenBlackedOut)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            updateIPs()
            cameraManager.setupCamera() // Show preview even if not streaming
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            cameraManager.stop()
            autoBlackoutTimer?.invalidate()
            UIScreen.main.brightness = previousBrightness
        }
    }
    
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

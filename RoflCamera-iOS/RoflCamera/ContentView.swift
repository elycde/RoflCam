import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var serverIPs: [String] = []
    @State private var isScreenBlackedOut = false
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var autoBlackoutTimer: Timer?
    
    let resolutions = ["3840x2160", "1920x1080", "1280x720", "640x480"]
    let fpsList = [30, 60]
    
    var body: some View {
        ZStack {
            if isScreenBlackedOut {
                Color.black.edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        wakeScreen()
                    }
                VStack {
                    Spacer()
                    Text("Коснитесь экрана для пробуждения")
                        .foregroundColor(.gray)
                        .padding()
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("RoflCamera")
                            .font(.largeTitle)
                            .bold()
                            .padding(.top, 20)
                        
                        if cameraManager.isRunning {
                            Text("Камера активна 🎥")
                                .foregroundColor(.green)
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Настройки сервера:")
                                    .font(.headline)
                                
                                Text("Wi-Fi:")
                                    .bold()
                                if serverIPs.isEmpty {
                                    Text("Получение IP...")
                                } else {
                                    ForEach(serverIPs, id: \.self) { ip in
                                        Text("http://\(ip):8080")
                                            .textSelection(.enabled)
                                    }
                                }
                                
                                Text("USB:")
                                    .bold()
                                    .padding(.top, 5)
                                Text("Программа для ПК подключится автоматически.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            
                            Button(action: {
                                cameraManager.stop()
                            }) {
                                Text("Остановить стрим")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red)
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                blackoutScreen()
                            }) {
                                Text("Выключить экран (Энергосбережение)")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            
                            VStack {
                                Text("Текущие параметры (синхронизируются с ПК):")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 10)
                                Text("\(cameraManager.currentResolutionString) @ \(cameraManager.currentFPS) FPS")
                                    .bold()
                            }
                            
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Настройки по умолчанию")
                                    .font(.headline)
                                
                                HStack {
                                    Text("Разрешение:")
                                    Spacer()
                                    Picker("Разрешение", selection: $cameraManager.currentResolutionString) {
                                        ForEach(resolutions, id: \.self) { res in
                                            Text(res).tag(res)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                                
                                HStack {
                                    Text("Частота кадров:")
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
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            
                            Button(action: {
                                cameraManager.start()
                                updateIPs()
                                startAutoBlackoutTimer()
                            }) {
                                Text("Запустить камеру")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.green)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .onTapGesture {
                    resetAutoBlackoutTimer()
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            updateIPs()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            cameraManager.stop()
            autoBlackoutTimer?.invalidate()
            UIScreen.main.brightness = previousBrightness
        }
    }
    
    // Получение IP-адресов устройства в локальной сети
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
                // en0 обычно отвечает за Wi-Fi
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

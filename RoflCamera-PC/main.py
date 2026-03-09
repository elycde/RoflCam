import os
import sys
import threading
import time
import subprocess
import cv2
import requests
import numpy as np
import pyvirtualcam
import customtkinter as ctk
from PIL import Image
from zeroconf import ServiceBrowser, Zeroconf

ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("blue")

class DiscoveredCamera:
    def __init__(self, name, ip, port):
        self.name = name
        self.ip = ip
        self.port = port
        self.url = f"http://{ip}:{port}"
        self.stream_state = False

class StreamingThread(threading.Thread):
    def __init__(self, url, width, height, fps, update_callback, error_callback):
        super().__init__(daemon=True)
        self.url = url
        self.width = width
        self.height = height
        self.fps = fps
        self.update_callback = update_callback
        self.error_callback = error_callback
        
        self.is_running = True
        self.latest_jpg = None

    def network_reader_loop(self):
        import urllib.request
        try:
            stream = urllib.request.urlopen(self.url, timeout=5)
            bytes_buffer = b''
            
            while self.is_running:
                chunk = stream.read(32768)
                if not chunk:
                    break
                bytes_buffer += chunk
                
                a = bytes_buffer.find(b'\xff\xd8')
                b = bytes_buffer.find(b'\xff\xd9')
                if a != -1 and b != -1:
                    # If multiple frames arrived quickly, jump to the most recent one
                    next_a = bytes_buffer.find(b'\xff\xd8', b+2)
                    if next_a != -1 and bytes_buffer.find(b'\xff\xd9', next_a) != -1:
                        bytes_buffer = bytes_buffer[next_a:]
                        continue
                        
                    self.latest_jpg = bytes_buffer[a:b+2]
                    bytes_buffer = bytes_buffer[b+2:]
        except Exception as e:
            if self.is_running:
                self.error_callback(f"Ошибка чтения сети: {str(e)}")
            self.is_running = False

    def run(self):
        time.sleep(0.5)
        
        vcam = None
        try:
            vcam = pyvirtualcam.Camera(width=self.width, height=self.height, fps=self.fps)
        except Exception:
            pass
            
        reader_thread = threading.Thread(target=self.network_reader_loop, daemon=True)
        reader_thread.start()
        
        last_processed_jpg = None
        
        try:
            while self.is_running:
                jpg = self.latest_jpg
                if jpg is None or jpg == last_processed_jpg:
                    time.sleep(0.005)
                    continue
                    
                last_processed_jpg = jpg
                
                frame = cv2.imdecode(np.frombuffer(jpg, dtype=np.uint8), cv2.IMREAD_COLOR)
                if frame is not None:
                    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    
                    if vcam:
                        try:
                            h, w, _ = frame_rgb.shape
                            if w != self.width or h != self.height:
                                frame_for_vcam = cv2.resize(frame_rgb, (self.width, self.height))
                            else:
                                frame_for_vcam = frame_rgb
                            vcam.send(frame_for_vcam)
                            # Removed vcam.sleep_until_next_frame() to eliminate network backpressure delay!
                        except:
                            pass
                            
                    # Обновление UI
                    try:
                        # Use fixed bounding box for UI to prevent window-resizing feedback loop
                        h, w, _ = frame_rgb.shape
                        ui_max_w, ui_max_h = 800, 600
                            
                        scale = min(ui_max_w / w, ui_max_h / h)
                        new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
                        frame_resized = cv2.resize(frame_rgb, (new_w, new_h))
                        
                        img = Image.fromarray(frame_resized)
                        ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(new_w, new_h))
                        self.update_callback(ctk_img)
                    except Exception:
                        pass
        except Exception as e:
            self.error_callback(f"Ошибка стрима: {str(e)}")
            self.is_running = False

        if vcam:
            vcam.close()

    def stop(self):
        self.is_running = False

class CameraPanel(ctk.CTkFrame):
    def __init__(self, master, camera: DiscoveredCamera, **kwargs):
        super().__init__(master, **kwargs)
        self.camera = camera
        self.stream_thread = None
        self.usb_forwarder = None
        
        # Upper bar (Settings)
        self.top_bar = ctk.CTkFrame(self, fg_color="transparent")
        self.top_bar.pack(fill="x", padx=10, pady=10)
        
        self.title_lbl = ctk.CTkLabel(self.top_bar, text=camera.name, font=ctk.CTkFont(size=16, weight="bold"))
        self.title_lbl.pack(side="left", padx=10)
        
        self.conn_type_var = ctk.StringVar(value="Wi-Fi")
        self.conn_radio_wifi = ctk.CTkRadioButton(self.top_bar, text="Wi-Fi", variable=self.conn_type_var, value="Wi-Fi", command=self.on_setting_changed)
        self.conn_radio_wifi.pack(side="left", padx=10)
        self.conn_radio_usb = ctk.CTkRadioButton(self.top_bar, text="USB (Кабель)", variable=self.conn_type_var, value="USB", command=self.on_setting_changed)
        self.conn_radio_usb.pack(side="left", padx=10)
        
        self.res_var = ctk.StringVar(value="1920x1080")
        self.res_menu = ctk.CTkOptionMenu(self.top_bar, variable=self.res_var, values=["3840x2160", "1920x1080", "1280x720", "640x480"], width=100, command=self.on_setting_changed)
        self.res_menu.pack(side="left", padx=10)
        
        self.fps_var = ctk.StringVar(value="30")
        self.fps_menu = ctk.CTkOptionMenu(self.top_bar, variable=self.fps_var, values=["30", "60", "120"], width=70, command=self.on_setting_changed)
        self.fps_menu.pack(side="left", padx=10)
        
        self.lens_var = ctk.StringVar(value="Осн. камера")
        self.lens_menu = ctk.CTkOptionMenu(self.top_bar, variable=self.lens_var, values=["Осн. камера", "Ширик", "Фронталка", "Телевик"], width=110, command=self.on_setting_changed)
        self.lens_menu.pack(side="left", padx=10)
        
        self.flash_var = ctk.BooleanVar(value=False)
        self.flash_cb = ctk.CTkCheckBox(self.top_bar, text="Фонарик", variable=self.flash_var, command=self.on_setting_changed)
        self.flash_cb.pack(side="left", padx=10)
        
        self.toggle_btn = ctk.CTkButton(self.top_bar, text="▶ Подключиться", command=self.toggle_stream, fg_color="green", hover_color="darkgreen")
        self.toggle_btn.pack(side="right", padx=10)
        
        # Display Area
        self.display_area = ctk.CTkLabel(self, text="Нажмите 'Подключиться' для создания виртуальной RoflCam", fg_color="black", text_color="gray", corner_radius=10)
        self.display_area.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        
        self.status_lbl = ctk.CTkLabel(self, text=f"Доступно по адресу: {camera.url}", text_color="gray")
        self.status_lbl.pack(side="bottom", pady=5)
        
    def send_settings_to_iphone(self):
        lens_map = {"Осн. камера": "back", "Ширик": "ultrawide", "Фронталка": "front", "Телевик": "telephoto"}
        lens = lens_map.get(self.lens_var.get(), "back")
        flash = "1" if self.flash_var.get() else "0"
        
        stream_url = f"http://127.0.0.1:{self.camera.port}" if self.conn_type_var.get() == "USB" else self.camera.url
        settings_url = f"{stream_url}/settings?res={self.res_var.get()}&fps={self.fps_var.get()}&lens={lens}&flash={flash}"
        
        def push_settings():
            try:
                requests.get(settings_url, timeout=2)
            except:
                pass
        threading.Thread(target=push_settings, daemon=True).start()
        
    def on_setting_changed(self, _=None):
        if self.camera.stream_state:
            self.send_settings_to_iphone()
            
            w, h = map(int, self.res_var.get().split('x'))
            fps = int(self.fps_var.get())
            
            need_restart = False
            if self.stream_thread:
                if self.stream_thread.width != w or self.stream_thread.height != h or self.stream_thread.fps != fps:
                    need_restart = True
                    
            if need_restart:
                self.stop_stream()
                self.after(500, self.start_stream)
    def toggle_stream(self):
        if self.camera.stream_state:
            self.stop_stream()
        else:
            self.start_stream()
            
    def start_stream(self):
        self.camera.stream_state = True
        self.toggle_btn.configure(text="■ Отключить", fg_color="red", hover_color="darkred")
        
        conn_type = self.conn_type_var.get()
        stream_url = self.camera.url
        
        if conn_type == "USB":
            self.status_lbl.configure(text="Статус: Запуск USB...", text_color="yellow")
            try:
                self.usb_forwarder = subprocess.Popen(
                    [sys.executable, "-m", "pymobiledevice3", "usbmux", "forward", str(self.camera.port), str(self.camera.port)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
                )
                time.sleep(1)
                stream_url = f"http://127.0.0.1:{self.camera.port}"
                self.status_lbl.configure(text="Статус: USB Подключено", text_color="green")
            except Exception as e:
                self.status_lbl.configure(text=f"Ошибка USB: {e}", text_color="red")
                self.stop_stream()
                return
        else:
            self.status_lbl.configure(text=f"Статус: Подключение по Wi-Fi ({stream_url})", text_color="green")

        self.send_settings_to_iphone()


        w, h = map(int, self.res_var.get().split('x'))
        fps = int(self.fps_var.get())
        
        self.stream_thread = StreamingThread(
            stream_url, w, h, fps, 
            update_callback=self.update_frame, 
            error_callback=self.handle_error
        )
        self.stream_thread.start()

    def stop_stream(self):
        self.camera.stream_state = False
        self.toggle_btn.configure(text="▶ Подключиться", fg_color="green", hover_color="darkgreen")
        self.status_lbl.configure(text="Отключено", text_color="gray")
        
        empty_img = ctk.CTkImage(light_image=Image.new("RGB", (1, 1)), size=(1, 1))
        self.display_area.configure(image=empty_img, text="Отключено.")
        
        if self.stream_thread:
            self.stream_thread.stop()
            self.stream_thread = None
            
        if self.usb_forwarder:
            self.usb_forwarder.terminate()
            self.usb_forwarder = None
            
    def update_frame(self, image):
        if self.camera.stream_state:
            self.after(0, lambda: self.display_area.configure(image=image, text=""))
            
    def handle_error(self, err_msg):
        self.after(0, lambda: self.status_lbl.configure(text=err_msg, text_color="red"))
        self.after(0, self.stop_stream)

class App(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("RoflCam Studio")
        self.geometry("1000x700")
        
        # Discovery variables
        self.zeroconf = Zeroconf()
        self.discovered_cameras = {}
        
        # Grid
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=1)
        
        self.tabs = ctk.CTkTabview(self)
        self.tabs.grid(row=0, column=0, sticky="nsew", padx=10, pady=10)
        
        # Start looking for cameras
        self.browser = ServiceBrowser(self.zeroconf, "_roflcam._tcp.local.", self)
        
        # Aggressive explicit subnet scanning
        self.scan_subnet()
        
    def scan_subnet(self):
        def do_scan():
            import socket
            import concurrent.futures
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                s.connect(('10.255.255.255', 1))
                local_ip = s.getsockname()[0]
            except Exception:
                local_ip = '127.0.0.1'
            finally:
                s.close()
                
            if local_ip == '127.0.0.1': return
            base_ip = ".".join(local_ip.split(".")[:-1]) + "."
            
            def check_ip(i):
                test_ip = base_ip + str(i)
                try:
                    # Quick check for RoflCam
                    r = requests.get(f"http://{test_ip}:8080/ping", timeout=0.3)
                    if "ROFLCAM_OK" in r.text.upper():
                        name = f"Найденная ({test_ip})"
                        self.after(0, self.add_camera_tab, name, test_ip, 8080)
                except Exception:
                    pass
            
            with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
                list(executor.map(check_ip, range(1, 255)))
                
        threading.Thread(target=do_scan, daemon=True).start()
        
    def add_service(self, zeroconf, type, name):
        info = zeroconf.get_service_info(type, name)
        if info:
            ip = ".".join([str(x) for x in info.addresses[0]])
            port = info.port
            clean_name = name.replace("._roflcam._tcp.local.", "").replace("RoflCam-", "Камера №")
            
            # Switch to main thread for UI changes
            self.after(0, self.add_camera_tab, clean_name, ip, port)

    def remove_service(self, zeroconf, type, name):
        clean_name = name.replace("._roflcam._tcp.local.", "").replace("RoflCam-", "Камера №")
        self.after(0, self.remove_camera_tab, clean_name)

    def update_service(self, zeroconf, type, name):
        pass
        
    def add_camera_tab(self, name, ip, port):
        # Check if this IP or Name already exists to prevent duplication
        for existing_cam in self.discovered_cameras.values():
            if existing_cam.ip == ip:
                return
        if name in self.discovered_cameras:
            return
            
        cam = DiscoveredCamera(name, ip, port)
        self.discovered_cameras[name] = cam
        
        self.tabs.add(name)
        panel = CameraPanel(self.tabs.tab(name), cam)
        panel.pack(fill="both", expand=True)
        
    def remove_camera_tab(self, name):
        if name in self.discovered_cameras:
            # Stop stream if running
            # In a real app we might traverse children and call stop()
            self.tabs.delete(name)
            self.discovered_cameras.pop(name, None)
            
    def on_closing(self):
        self.zeroconf.close()
        self.destroy()

if __name__ == "__main__":
    os.environ["PYMOBILEDEVICE3_DISABLE_WARNINGS"] = "1"
    # Create manual instruction if no devices found
    app = App()
    
    # Adding manual override tab just in case auto-discovery fails
    app.tabs.add("Добавить вручную (IP)")
    manual_frame = ctk.CTkFrame(app.tabs.tab("Добавить вручную (IP)"))
    manual_frame.pack(fill="both", expand=True)
    
    ctk.CTkLabel(manual_frame, text="Если авто-обнаружение по Wi-Fi не сработало, введите данные ниже:").pack(pady=20)
    manual_ip = ctk.CTkEntry(manual_frame, placeholder_text="192.168.1.100")
    manual_ip.pack(pady=10)
    manual_port = ctk.CTkEntry(manual_frame, placeholder_text="8080")
    manual_port.pack(pady=10)
    
    def connect_manual():
        n = f"Ручная Камера ({manual_ip.get()})"
        if n not in app.discovered_cameras:
            app.add_camera_tab(n, manual_ip.get(), int(manual_port.get() or "8080"))
            app.tabs.set(n)
            
    ctk.CTkButton(manual_frame, text="Добавить эту камеру", command=connect_manual).pack(pady=20)
    
    app.protocol("WM_DELETE_WINDOW", app.on_closing)
    app.mainloop()

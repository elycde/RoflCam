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
from PIL import Image, ImageTk

ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

class RoflCameraApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        
        self.title("RoflCamera Companion")
        self.geometry("850x650")
        
        self.is_running = False
        self.forwarder_process = None
        self.camera_thread = None
        
        # UI Setup
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)
        
        # Sidebar
        self.sidebar_frame = ctk.CTkFrame(self, width=250, corner_radius=0)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(8, weight=1)
        
        self.logo_label = ctk.CTkLabel(self.sidebar_frame, text="RoflCamera", font=ctk.CTkFont(size=20, weight="bold"))
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 10))
        
        self.conn_type_var = ctk.StringVar(value="USB")
        self.conn_type_usb = ctk.CTkRadioButton(self.sidebar_frame, text="USB (Кабель)", variable=self.conn_type_var, value="USB", command=self.update_ui)
        self.conn_type_usb.grid(row=1, column=0, pady=10, padx=20, sticky="w")
        
        self.conn_type_wifi = ctk.CTkRadioButton(self.sidebar_frame, text="Wi-Fi", variable=self.conn_type_var, value="WIFI", command=self.update_ui)
        self.conn_type_wifi.grid(row=2, column=0, pady=10, padx=20, sticky="w")
        
        self.ip_entry = ctk.CTkEntry(self.sidebar_frame, placeholder_text="IP адрес (напр. 192.168.1.5)")
        self.ip_entry.grid(row=3, column=0, pady=10, padx=20, sticky="ew")
        self.ip_entry.configure(state="disabled")
        
        # Settings
        self.settings_label = ctk.CTkLabel(self.sidebar_frame, text="Настройки камеры:", font=ctk.CTkFont(weight="bold"))
        self.settings_label.grid(row=4, column=0, pady=(20, 0), padx=20, sticky="w")
        
        self.res_var = ctk.StringVar(value="1920x1080")
        self.res_menu = ctk.CTkOptionMenu(self.sidebar_frame, variable=self.res_var, values=["3840x2160", "1920x1080", "1280x720", "640x480"])
        self.res_menu.grid(row=5, column=0, pady=10, padx=20, sticky="ew")
        
        self.fps_var = ctk.StringVar(value="30")
        self.fps_menu = ctk.CTkOptionMenu(self.sidebar_frame, variable=self.fps_var, values=["30", "60"])
        self.fps_menu.grid(row=6, column=0, pady=10, padx=20, sticky="ew")
        
        self.start_btn = ctk.CTkButton(self.sidebar_frame, text="Запустить трансляцию", command=self.toggle_stream)
        self.start_btn.grid(row=7, column=0, pady=20, padx=20)
        
        self.status_label = ctk.CTkLabel(self.sidebar_frame, text="Статус: Отключено", text_color="gray")
        self.status_label.grid(row=9, column=0, pady=20, padx=20, sticky="s")
        
        # Main content
        self.main_frame = ctk.CTkFrame(self)
        self.main_frame.grid(row=0, column=1, sticky="nsew", padx=10, pady=10)
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(0, weight=1)
        
        self.video_label = ctk.CTkLabel(self.main_frame, text="Ожидание подключения...")
        self.video_label.grid(row=0, column=0, sticky="nsew")
        
        info_text = ("Как добавить в OBS: Добавьте источник 'Браузер' или 'Источник медиа', URL: http://127.0.0.1:8080\\n"
                     "Или используйте в OBS 'Virtual Camera' (она сама подцепит этот поток в систему).")
        self.info_label = ctk.CTkLabel(self.main_frame, text=info_text)
        self.info_label.grid(row=1, column=0, pady=10)
        
    def update_ui(self):
        if self.conn_type_var.get() == "WIFI":
            self.ip_entry.configure(state="normal")
        else:
            self.ip_entry.configure(state="disabled")
            
    def toggle_stream(self):
        if self.is_running:
            self.stop_stream()
        else:
            self.start_stream()
            
    def start_stream(self):
        self.is_running = True
        self.start_btn.configure(text="Остановить трансляцию", fg_color="red", hover_color="darkred")
        
        # Disable dropdowns while running
        self.res_menu.configure(state="disabled")
        self.fps_menu.configure(state="disabled")
        
        conn_type = self.conn_type_var.get()
        stream_url = ""
        
        if conn_type == "USB":
            self.status_label.configure(text="Статус: Запуск USB...", text_color="yellow")
            try:
                self.forwarder_process = subprocess.Popen(
                    [sys.executable, "-m", "pymobiledevice3", "forward", "8080", "8080"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
                )
                time.sleep(1)
                stream_url = "http://127.0.0.1:8080"
                self.status_label.configure(text="Статус: USB Подключено", text_color="green")
            except Exception as e:
                self.status_label.configure(text=f"Ошибка: {e}", text_color="red")
                self.stop_stream()
                return
        else:
            ip = self.ip_entry.get().strip()
            if not ip:
                self.status_label.configure(text="Ошибка: Введите IP", text_color="red")
                self.stop_stream()
                return
            if not ip.startswith('http'):
                stream_url = f"http://{ip}:8080"
            else:
                stream_url = f"{ip}:8080"
            self.status_label.configure(text="Статус: Wi-Fi Ожидание", text_color="yellow")
            
        # Send settings to sync with iPhone over network
        # Fire-and-forget request
        def send_settings():
            try:
                settings_url = f"{stream_url}/settings?res={self.res_var.get()}&fps={self.fps_var.get()}"
                requests.get(settings_url, timeout=2)
            except Exception as e:
                print(f"Could not sync settings instantly: {e}")
                
        threading.Thread(target=send_settings, daemon=True).start()
            
        self.camera_thread = threading.Thread(target=self.process_stream, args=(stream_url,), daemon=True)
        self.camera_thread.start()
        
    def stop_stream(self):
        self.is_running = False
        self.start_btn.configure(text="Запустить трансляцию", fg_color=['#3B8ED0', '#1F6AA5'], hover_color=['#36719F', '#144870'])
        self.status_label.configure(text="Статус: Отключено", text_color="gray")
        self.video_label.configure(image="", text="Отключено")
        
        self.res_menu.configure(state="normal")
        self.fps_menu.configure(state="normal")
        
        if self.forwarder_process:
            self.forwarder_process.terminate()
            self.forwarder_process = None
            
    def process_stream(self, url):
        # We add a slight delay to allow iPhone to reconfigure its internal properties first
        time.sleep(0.5)
        cap = cv2.VideoCapture(url)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        
        if not cap.isOpened():
            self.status_label.configure(text="Ошибка: Камера недоступна", text_color="red")
            self.stop_stream()
            return
            
        self.status_label.configure(text="Статус: Трансляция идет", text_color="green")
        
        vcam = None
        
        # Parse defined size
        wanted_res = self.res_var.get().split('x')
        v_width = int(wanted_res[0])
        v_height = int(wanted_res[1])
        v_fps = int(self.fps_var.get())

        try:
            vcam = pyvirtualcam.Camera(width=v_width, height=v_height, fps=v_fps)
            print(f'Virtual cam started: {vcam.device} ({vcam.width}x{vcam.height} @ {vcam.fps}fps)')
        except Exception as e:
            print(f"Не удалось запустить виртуальную камеру (OBS Virtual Camera not installed?): {e}")
            
        while self.is_running:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.01)
                continue
                
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            if vcam:
                try:
                    # In case MJPEG sends a slightly different resolution during init
                    h, w, _ = frame_rgb.shape
                    if w != v_width or h != v_height:
                        frame_for_vcam = cv2.resize(frame_rgb, (v_width, v_height))
                    else:
                        frame_for_vcam = frame_rgb
                    vcam.send(frame_for_vcam)
                    vcam.sleep_until_next_frame()
                except:
                    pass
            
            try:
                h, w, _ = frame_rgb.shape
                # Adaptive scale for UI preserving aspect ratio
                ui_max_w, ui_max_h = 600, 450
                scale = min(ui_max_w / w, ui_max_h / h)
                new_w, new_h = int(w * scale), int(h * scale)
                frame_resized = cv2.resize(frame_rgb, (new_w, new_h))
                
                img = Image.fromarray(frame_resized)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(new_w, new_h))
                
                self.after(0, self.update_image, ctk_img)
            except Exception as e:
                pass
                
        cap.release()
        if vcam:
            vcam.close()
            
    def update_image(self, image):
        if self.is_running:
            self.video_label.configure(image=image, text="")

if __name__ == "__main__":
    os.environ["PYMOBILEDEVICE3_DISABLE_WARNINGS"] = "1"
    app = RoflCameraApp()
    app.mainloop()

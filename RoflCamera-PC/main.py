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
        self.geometry("800x600")
        
        self.is_running = False
        self.forwarder_process = None
        self.camera_thread = None
        
        # UI Setup
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)
        
        # Sidebar
        self.sidebar_frame = ctk.CTkFrame(self, width=200, corner_radius=0)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(5, weight=1)
        
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
        
        self.start_btn = ctk.CTkButton(self.sidebar_frame, text="Запустить трансляцию", command=self.toggle_stream)
        self.start_btn.grid(row=4, column=0, pady=20, padx=20)
        
        self.status_label = ctk.CTkLabel(self.sidebar_frame, text="Статус: Отключено", text_color="gray")
        self.status_label.grid(row=6, column=0, pady=20, padx=20, sticky="s")
        
        # Main content
        self.main_frame = ctk.CTkFrame(self)
        self.main_frame.grid(row=0, column=1, sticky="nsew", padx=10, pady=10)
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(0, weight=1)
        
        self.video_label = ctk.CTkLabel(self.main_frame, text="Ожидание подключения...")
        self.video_label.grid(row=0, column=0, sticky="nsew")
        
        self.info_label = ctk.CTkLabel(self.main_frame, text="Как добавить в OBS: Добавьте источник 'Браузер' или 'Источник медиа', URL: http://127.0.0.1:8080\\nИли используйте встроенную виртуальную камеру OBS, которая автоматически получит этот видеопоток.")
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
        
        conn_type = self.conn_type_var.get()
        stream_url = ""
        
        if conn_type == "USB":
            self.status_label.configure(text="Статус: Запуск USB...", text_color="yellow")
            # Проброс портов через pymobiledevice3 (iPhone USB -> PC 8080)
            try:
                # Мы запускаем subprocess чтобы не блокировать и не крашить UI если сломается
                self.forwarder_process = subprocess.Popen(
                    [sys.executable, "-m", "pymobiledevice3", "forward", "8080", "8080"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
                )
                time.sleep(1) # Даем время на запуск
                stream_url = "http://127.0.0.1:8080"
                self.status_label.configure(text="Статус: USB Подключено", text_color="green")
            except Exception as e:
                self.status_label.configure(text=f"Ошибка: {e}", text_color="red")
                self.stop_stream()
                return
        else:
            ip = self.ip_entry.get()
            if not ip:
                self.status_label.configure(text="Ошибка: Введите IP", text_color="red")
                self.stop_stream()
                return
            stream_url = f"http://{ip}:8080"
            self.status_label.configure(text="Статус: Wi-Fi Ожидание", text_color="yellow")
            
        self.camera_thread = threading.Thread(target=self.process_stream, args=(stream_url,), daemon=True)
        self.camera_thread.start()
        
    def stop_stream(self):
        self.is_running = False
        self.start_btn.configure(text="Запустить трансляцию", fg_color=['#3B8ED0', '#1F6AA5'], hover_color=['#36719F', '#144870'])
        self.status_label.configure(text="Статус: Отключено", text_color="gray")
        self.video_label.configure(image="", text="Отключено")
        
        if self.forwarder_process:
            self.forwarder_process.terminate()
            self.forwarder_process = None
            
    def process_stream(self, url):
        cap = cv2.VideoCapture(url)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1) # Минимизируем задержку
        
        if not cap.isOpened():
            self.status_label.configure(text="Ошибка: Камера недоступна", text_color="red")
            self.stop_stream()
            return
            
        self.status_label.configure(text="Статус: Трансляция идет", text_color="green")
        
        # Настройка виртуальной камеры
        vcam = None
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = 30
        
        # Если cv2 не определил ширину/высоту (что бывает с MJPEG), поставим 1920x1080
        if width == 0 or height == 0:
            width, height = 1920, 1080

        try:
            # OBS Virtual Camera должна быть установлена и включена в системе
            vcam = pyvirtualcam.Camera(width=width, height=height, fps=fps)
            print(f'Virtual cam started: {vcam.device} ({vcam.width}x{vcam.height} @ {vcam.fps}fps)')
        except Exception as e:
            print(f"Не удалось запустить виртуальную камеру: {e}")
            # Мы продолжим без виртуальной камеры, просто показывая в UI
            
        while self.is_running:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.1)
                continue
                
            # OpenCV использует BGR, переводим в RGB для UI и VirtualCam
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Отправляем в виртуальную камеру Windows
            if vcam:
                try:
                    vcam.send(frame_rgb)
                    vcam.sleep_until_next_frame()
                except:
                    pass
            
            # Обновляем UI (сжимаем картинку для окна)
            try:
                h, w, _ = frame_rgb.shape
                # Масштабируем до 600 в ширину для превью
                scale = 600 / w
                new_w, new_h = int(w * scale), int(h * scale)
                frame_resized = cv2.resize(frame_rgb, (new_w, new_h))
                
                img = Image.fromarray(frame_resized)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(new_w, new_h))
                
                # Используем after(0) для обновления из другого потока
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
    # Патч для работы на Windows без лишних проблем с asyncio/pymobiledevice3
    os.environ["PYMOBILEDEVICE3_DISABLE_WARNINGS"] = "1"
    app = RoflCameraApp()
    app.mainloop()

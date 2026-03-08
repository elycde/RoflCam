import urllib.request
import time
import sys

def run(url):
    s = time.time()
    try:
        stream = urllib.request.urlopen(url, timeout=5)
    except Exception as e:
        print(f"Connection failed: {e}")
        return
    print(f"Connected in {time.time() - s:.3f}s")
    
    frames = 0
    start = time.time()
    b = b''
    while frames < 30:
        b += stream.read(8192)
        idx = b.find(b'\xff\xd9')
        if idx != -1:
            frames += 1
            b = b[idx+2:]
            
    dur = time.time() - start
    print(f"30 frames received in {dur:.3f}s ({30/dur:.1f} FPS, {dur/30*1000:.1f}ms per frame)")

run("http://192.168.0.188:8080/")

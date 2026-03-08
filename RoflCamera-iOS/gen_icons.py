import os
from PIL import Image
import json

icon_path = "../icon.png"
if not os.path.exists(icon_path):
    print("Icon not found")
    exit(1)

base_img = Image.open(icon_path).convert("RGBA")

appiconset_path = "RoflCam/Assets.xcassets/AppIcon.appiconset"
os.makedirs(appiconset_path, exist_ok=True)

sizes = [
    (20, 1), (20, 2), (20, 3),
    (29, 1), (29, 2), (29, 3),
    (40, 1), (40, 2), (40, 3),
    (60, 2), (60, 3),
    (76, 1), (76, 2),
    (83.5, 2),
    (1024, 1)
]

contents = {"images": [], "info": {"author": "xcode", "version": 1}}

for size, scale in sizes:
    px_size = int(size * scale)
    filename = f"Icon-{size}x{size}@{scale}x.png"
    filepath = os.path.join(appiconset_path, filename)
    
    resized = base_img.resize((px_size, px_size), Image.Resampling.LANCZOS)
    resized.save(filepath)
    
    contents["images"].append({
        "size": f"{size}x{size}",
        "idiom": "universal",
        "filename": filename,
        "scale": f"{scale}x"
    })

# Overwrite some idioms for iPad / iPhone specifics if needed, but universal is fine for Xcode 14+ / iOS 15
with open(os.path.join(appiconset_path, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

print("Icons generated!")

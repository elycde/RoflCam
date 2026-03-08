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
    (20, 1, "ipad"), (20, 2, "ipad"), (20, 2, "iphone"), (20, 3, "iphone"),
    (29, 1, "ipad"), (29, 2, "ipad"), (29, 2, "iphone"), (29, 3, "iphone"),
    (40, 1, "ipad"), (40, 2, "ipad"), (40, 2, "iphone"), (40, 3, "iphone"),
    (60, 2, "iphone"), (60, 3, "iphone"),
    (76, 1, "ipad"), (76, 2, "ipad"),
    (83.5, 2, "ipad"),
    (1024, 1, "ios-marketing")
]

contents = {"images": [], "info": {"author": "xcode", "version": 1}}

for size, scale, idiom in sizes:
    px_size = int(size * scale)
    filename = f"Icon-{size}x{size}@{scale}x-{idiom}.png"
    filepath = os.path.join(appiconset_path, filename)
    
    resized = base_img.resize((px_size, px_size), Image.Resampling.LANCZOS)
    resized.save(filepath)
    
    contents["images"].append({
        "size": f"{size}x{size}" if size != 83.5 else "83.5x83.5",
        "idiom": idiom,
        "filename": filename,
        "scale": f"{scale}x"
    })

# Overwrite some idioms for iPad / iPhone specifics if needed, but universal is fine for Xcode 14+ / iOS 15
with open(os.path.join(appiconset_path, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

print("Icons generated!")

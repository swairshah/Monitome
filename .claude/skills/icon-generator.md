# Icon Generator Skill

Generate macOS app and menu bar icons from source images.

## Menu Bar Icons

From `monitome-menubar.png`, generate template icons for macOS menu bar:

```bash
# Required sizes (template images should be black with transparency)
sips -z 16 16 monitome-menubar.png --out Monitome/Assets.xcassets/MenuBarIcon.imageset/icon-16.png
sips -z 32 32 monitome-menubar.png --out Monitome/Assets.xcassets/MenuBarIcon.imageset/icon-16@2x.png
sips -z 18 18 monitome-menubar.png --out Monitome/Assets.xcassets/MenuBarIcon.imageset/icon-18.png
sips -z 36 36 monitome-menubar.png --out Monitome/Assets.xcassets/MenuBarIcon.imageset/icon-18@2x.png
```

Create `Monitome/Assets.xcassets/MenuBarIcon.imageset/Contents.json`:
```json
{
  "images": [
    {"filename": "icon-16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
    {"filename": "icon-16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
    {"filename": "icon-18.png", "idiom": "mac", "scale": "1x", "size": "18x18"},
    {"filename": "icon-18@2x.png", "idiom": "mac", "scale": "2x", "size": "18x18"}
  ],
  "info": {"author": "xcode", "version": 1},
  "properties": {"preserves-vector-representation": true, "template-rendering-intent": "template"}
}
```

## App Icons

From `monitome-app.png` (should be 1024x1024), generate all required sizes:

```bash
SOURCE="monitome-app.png"
OUT="Monitome/Assets.xcassets/AppIcon.appiconset"

sips -z 16 16 $SOURCE --out $OUT/icon-16.png
sips -z 32 32 $SOURCE --out $OUT/icon-16@2x.png
sips -z 32 32 $SOURCE --out $OUT/icon-32.png
sips -z 64 64 $SOURCE --out $OUT/icon-32@2x.png
sips -z 128 128 $SOURCE --out $OUT/icon-128.png
sips -z 256 256 $SOURCE --out $OUT/icon-128@2x.png
sips -z 256 256 $SOURCE --out $OUT/icon-256.png
sips -z 512 512 $SOURCE --out $OUT/icon-256@2x.png
sips -z 512 512 $SOURCE --out $OUT/icon-512.png
sips -z 1024 1024 $SOURCE --out $OUT/icon-512@2x.png
```

Create `Monitome/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images": [
    {"filename": "icon-16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
    {"filename": "icon-16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
    {"filename": "icon-32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
    {"filename": "icon-32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
    {"filename": "icon-128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
    {"filename": "icon-128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
    {"filename": "icon-256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
    {"filename": "icon-256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
    {"filename": "icon-512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
    {"filename": "icon-512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"}
  ],
  "info": {"author": "xcode", "version": 1}
}
```

## Usage

1. Place source images in project root:
   - `monitome-app.png` (1024x1024, full color)
   - `monitome-menubar.png` (simple, black on transparent, ~128x128)

2. Run the commands above or ask Claude: "generate icons from monitome-app.png"

## Notes

- Menu bar icons should be "template" images: black shapes on transparent background. macOS will colorize them automatically.
- App icon should be full color, 1024x1024, no transparency.
- Use `sips` (built into macOS) - no external tools needed.

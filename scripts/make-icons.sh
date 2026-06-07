#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate the iOS AppIcon set from the PharosVPN beacon mark.
#
# iOS 14+ accepts a single 1024×1024 "any-appearance" icon (Xcode generates the
# downscaled variants at build time), but we render every classic size too so the
# set works on older toolchains and shows crisp in every slot.
#
# IMPORTANT: render with an ALPHA-PRESERVING rasterizer (resvg / rsvg-convert) —
# NEVER qlmanage, which flattens transparency onto white. The marketing 1024 icon
# must have NO alpha channel, so we flatten it to RGB at the end.
#
#   brew install resvg        # or: brew install librsvg  (rsvg-convert)
#   ./scripts/make-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.assets/icon-ios.svg"          # full-bleed maroon (no transparent corners)
OUT="$ROOT/app/Caravel/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$OUT"

# --- pick a rasterizer ---
if command -v resvg >/dev/null 2>&1; then
  render() { resvg -w "$1" -h "$1" "$SRC" "$2"; }
elif command -v rsvg-convert >/dev/null 2>&1; then
  render() { rsvg-convert -w "$1" -h "$1" "$SRC" -o "$2"; }
else
  echo "error: need resvg or rsvg-convert (brew install resvg)" >&2
  exit 1
fi

echo "→ rendering icons from $(basename "$SRC")…"
# iPhone/iPad slot sizes (pt × scale) plus the 1024 marketing icon. 20/29 cover
# the iPad 1x notification/settings slots so every slot is an exact-size file.
for px in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
  render "$px" "$OUT/icon_${px}.png"
  printf "  %4dpx\n" "$px"
done

# The App Store 1024 icon must be OPAQUE RGB (no alpha channel) or App Store
# Connect rejects it. sips can't reliably drop the channel, so flatten via a tiny
# CoreGraphics helper compiled on the fly (composites onto the maroon background).
FLAT="$(mktemp -d)/flatten.swift"
cat > "$FLAT" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
guard a.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }
let w = img.width, h = img.height
guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
ctx.setFillColor(red: 0x5A/255.0, green: 0x1F/255.0, blue: 0x2B/255.0, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
guard let out = ctx.makeImage(),
      let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
        UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dst, out, nil)
CGImageDestinationFinalize(dst)
SWIFT
if command -v swiftc >/dev/null 2>&1; then
  BIN="$(dirname "$FLAT")/flatten"
  swiftc -O "$FLAT" -o "$BIN" 2>/dev/null && "$BIN" "$OUT/icon_1024.png" "$OUT/icon_1024.png" \
    && echo "  flattened icon_1024.png to opaque RGB" || echo "  (warn: could not flatten 1024 — set hasAlpha no in Xcode)"
fi

echo "→ writing Contents.json…"
cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "iphone", "scale" : "2x", "size" : "20x20",   "filename" : "icon_40.png" },
    { "idiom" : "iphone", "scale" : "3x", "size" : "20x20",   "filename" : "icon_60.png" },
    { "idiom" : "iphone", "scale" : "2x", "size" : "29x29",   "filename" : "icon_58.png" },
    { "idiom" : "iphone", "scale" : "3x", "size" : "29x29",   "filename" : "icon_87.png" },
    { "idiom" : "iphone", "scale" : "2x", "size" : "40x40",   "filename" : "icon_80.png" },
    { "idiom" : "iphone", "scale" : "3x", "size" : "40x40",   "filename" : "icon_120.png" },
    { "idiom" : "iphone", "scale" : "2x", "size" : "60x60",   "filename" : "icon_120.png" },
    { "idiom" : "iphone", "scale" : "3x", "size" : "60x60",   "filename" : "icon_180.png" },
    { "idiom" : "ipad",   "scale" : "1x", "size" : "20x20",   "filename" : "icon_20.png" },
    { "idiom" : "ipad",   "scale" : "2x", "size" : "20x20",   "filename" : "icon_40.png" },
    { "idiom" : "ipad",   "scale" : "1x", "size" : "29x29",   "filename" : "icon_29.png" },
    { "idiom" : "ipad",   "scale" : "2x", "size" : "29x29",   "filename" : "icon_58.png" },
    { "idiom" : "ipad",   "scale" : "1x", "size" : "40x40",   "filename" : "icon_40.png" },
    { "idiom" : "ipad",   "scale" : "2x", "size" : "40x40",   "filename" : "icon_80.png" },
    { "idiom" : "ipad",   "scale" : "1x", "size" : "76x76",   "filename" : "icon_76.png" },
    { "idiom" : "ipad",   "scale" : "2x", "size" : "76x76",   "filename" : "icon_152.png" },
    { "idiom" : "ipad",   "scale" : "2x", "size" : "83.5x83.5", "filename" : "icon_167.png" },
    { "idiom" : "ios-marketing", "scale" : "1x", "size" : "1024x1024", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "✓ AppIcon set written to $OUT"

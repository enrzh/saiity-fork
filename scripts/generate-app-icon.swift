#!/usr/bin/env swift
// Legacy entry point retained for existing tooling. The checked-in sAi artwork
// is authoritative; never regenerate the retired three-bar Dictus icon.
import Foundation
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let icons = root.appendingPathComponent("DictusApp/Assets.xcassets/AppIcon.appiconset")
for name in ["AppIcon-1024.png", "AppIcon-1024-dark.png", "AppIcon-1024-tinted.png"] {
    let url = icons.appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          properties[kCGImagePropertyPixelWidth] as? Int == 1024,
          properties[kCGImagePropertyPixelHeight] as? Int == 1024 else {
        fatalError("Missing or invalid 1024-pixel sAi app icon: \(name)")
    }
}
print("Verified the three curated sAi icons. No artwork overwritten.")

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icon = resources.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.removeItem(at: icon)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

func makeImage(pixelSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let fontSize = pixelSize * 0.62
    let font = NSFont(name: "Apple Color Emoji", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraph
    ]
    let text = "🌳" as NSString
    let rect = NSRect(
        x: 0,
        y: pixelSize * 0.03,
        width: pixelSize,
        height: pixelSize
    )
    text.draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attributes)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "ForestIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try png.write(to: url)
}

for size in sizes {
    let pixels = size.points * size.scale
    let image = makeImage(pixelSize: pixels)
    try writePNG(image, to: iconset.appendingPathComponent(size.name))
}

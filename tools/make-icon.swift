// Generates Resources/AppIcon.icns — a dark rounded-square with a gold "MMR" wordmark.
// Run from the repo root:  swift tools/make-icon.swift Resources/AppIcon.icns
import Cocoa

func renderPNG(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = (s - 2 * inset) * 0.235
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(red: 0.17, green: 0.17, blue: 0.20, alpha: 1),
               ending: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))!.draw(in: path, angle: -90)
    NSColor(white: 1, alpha: 0.10).setStroke(); path.lineWidth = max(1, s * 0.008); path.stroke()
    let txt = "MMR" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.235, weight: .heavy),
        .foregroundColor: NSColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1.0)]
    let tsz = txt.size(withAttributes: attrs)
    txt.draw(at: NSPoint(x: (s - tsz.width) / 2, y: (s - tsz.height) / 2 - s * 0.01), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, px) in sizes { try! renderPNG(px).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png")) }
try? fm.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", "-o", out, iconset]
try! p.run(); p.waitUntilExit()
print("wrote \(out) (status \(p.terminationStatus))")

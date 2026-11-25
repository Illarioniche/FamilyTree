import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (points, scale) in sizes {
    let size = points * scale
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 198, yRadius: 198)
    let gradient = NSGradient(starting: NSColor(red: 0.40, green: 0.57, blue: 0.43, alpha: 1),
                              ending: NSColor(red: 0.16, green: 0.31, blue: 0.24, alpha: 1))!
    gradient.draw(in: background, angle: -90)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    background.lineWidth = 5; background.stroke()
    NSColor(red: 0.94, green: 0.96, blue: 0.87, alpha: 1).setStroke()
    let stem = NSBezierPath()
    stem.lineWidth = 26; stem.lineCapStyle = .round; stem.lineJoinStyle = .round
    stem.move(to: NSPoint(x: 512, y: 265))
    stem.curve(to: NSPoint(x: 512, y: 676), controlPoint1: NSPoint(x: 503, y: 415), controlPoint2: NSPoint(x: 530, y: 564))
    stem.move(to: NSPoint(x: 512, y: 435)); stem.line(to: NSPoint(x: 381, y: 527))
    stem.move(to: NSPoint(x: 512, y: 531)); stem.line(to: NSPoint(x: 648, y: 623))
    stem.stroke()
    func leaf(_ x: CGFloat, _ y: CGFloat, _ mirrored: Bool) {
        let leaf = NSBezierPath()
        let sign: CGFloat = mirrored ? -1 : 1
        leaf.move(to: NSPoint(x: x, y: y))
        leaf.curve(to: NSPoint(x: x + sign * 164, y: y + 151), controlPoint1: NSPoint(x: x - sign * 31, y: y + 122), controlPoint2: NSPoint(x: x + sign * 86, y: y + 170))
        leaf.curve(to: NSPoint(x: x, y: y), controlPoint1: NSPoint(x: x + sign * 167, y: y + 36), controlPoint2: NSPoint(x: x + sign * 96, y: y - 17))
        leaf.close()
        NSColor(red: 0.95, green: 0.97, blue: 0.88, alpha: 0.98).setFill(); leaf.fill()
    }
    leaf(392, 521, true)
    leaf(629, 615, false)
    leaf(509, 650, false)
    let roots = NSBezierPath()
    roots.lineWidth = 16; roots.lineCapStyle = .round
    roots.move(to: NSPoint(x: 443, y: 263)); roots.line(to: NSPoint(x: 581, y: 263)); roots.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}

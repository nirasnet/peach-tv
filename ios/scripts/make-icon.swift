// swift scripts/make-icon.swift <out.png>  - the 1024 px app icon: a peach on a little TV.
import AppKit
let size: CGFloat = 1024
// Opaque on purpose: App Store icons must not carry an alpha channel.
let cg = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let full = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [NSColor(red: 0.20, green: 0.09, blue: 0.07, alpha: 1), NSColor(red: 0.03, green: 0.015, blue: 0.01, alpha: 1)])!
    .draw(in: full, angle: -90)
NSGradient(colors: [NSColor(red: 1, green: 0.62, blue: 0.45, alpha: 0.35), NSColor(red: 1, green: 0.62, blue: 0.45, alpha: 0)])!
    .draw(fromCenter: NSPoint(x: size / 2, y: 540), radius: 0, toCenter: NSPoint(x: size / 2, y: 540), radius: 470, options: [])
let peach = NSColor(red: 1, green: 0.70, blue: 0.54, alpha: 1)
let screen = NSBezierPath(roundedRect: NSRect(x: 172, y: 282, width: 680, height: 470), xRadius: 70, yRadius: 70)
screen.lineWidth = 34
peach.setStroke()
screen.stroke()
let stand = NSBezierPath(roundedRect: NSRect(x: 372, y: 200, width: 280, height: 34), xRadius: 17, yRadius: 17)
peach.setFill()
stand.fill()
let emoji = NSAttributedString(string: "🍑", attributes: [.font: NSFont(name: "Apple Color Emoji", size: 330)!])
let box = emoji.size()
emoji.draw(at: NSPoint(x: (size - box.width) / 2, y: 517 - box.height / 2))
NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

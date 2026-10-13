// Synthetic OCR test input, not a photograph or a real parking restriction.
// Run: swift docs/store/test-assets/render-sample-sign.swift <output.png>
import AppKit
let size = NSSize(width: 1000, height: 1200)
let image = NSImage(size: size)
image.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor.black.setStroke()
let border = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 900, height: 1100), xRadius: 35, yRadius: 35)
border.lineWidth = 8
border.stroke()
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
for (text, y, font) in [("2 HOUR", 850.0, 104.0), ("PARKING", 695.0, 104.0), ("MON–FRI", 490.0, 82.0), ("9AM–6PM", 340.0, 82.0), ("EXAMPLE SIGN", 120.0, 32.0)] {
    (text as NSString).draw(in: NSRect(x: 65, y: y, width: 870, height: 135), withAttributes: [
        .font: NSFont.systemFont(ofSize: font, weight: .bold), .foregroundColor: NSColor.black, .paragraphStyle: paragraph
    ])
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

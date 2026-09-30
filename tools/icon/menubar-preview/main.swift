// A sheet comparing the vector menu bar glyph (Sources/MenubarDDCControl/MenuBarIcon.swift) with a
// greyscale downscale of the app icon, on light and dark menu bars, at 1x and 2x, magnified with
// nearest-neighbour so the real pixels are visible. This is how the glyph was chosen.
//
// Rows: vector on light, vector on dark, artwork on light, artwork on dark.
// Columns: 1x (shown 12x), 2x (shown 6x).
import AppKit

let artwork = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = URL(fileURLWithPath: CommandLine.arguments[2])

func render(scale: Int, bar: CGColor, ink: CGColor, vector: Bool) -> CGImage {
    let w = 24 * scale, h = 24 * scale
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(bar); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let glyph = CGRect(x: 3 * scale, y: 3 * scale, width: 18 * scale, height: 18 * scale)
    if vector {
        // Template rendering: draw the mask, then fill it with the menu bar's ink colour.
        let mask = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        MenuBarIcon.draw(in: mask, rect: glyph)
        ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: mask.makeImage()!)
        ctx.setFillColor(ink); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)); ctx.restoreGState()
    } else {
        let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let grey = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        grey.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        ctx.interpolationQuality = .high
        ctx.draw(grey.makeImage()!, in: glyph.insetBy(dx: -2 * CGFloat(scale), dy: -2 * CGFloat(scale)))
    }
    return ctx.makeImage()!
}

let light = CGColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1), dark = CGColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
let rows: [(Bool, CGColor, CGColor)] = [(true, light, CGColor(gray: 0, alpha: 0.85)), (true, dark, CGColor(gray: 1, alpha: 0.9)),
                                         (false, light, .black), (false, dark, .white)]
let zoom = 6, cell = 24 * 2 * zoom + 20
let sheet = CGContext(data: nil, width: cell * 2, height: cell * rows.count, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(gray: 0.5, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: cell * 2, height: cell * rows.count))
sheet.interpolationQuality = .none
for (r, (vector, bar, ink)) in rows.enumerated() {
    for (col, scale) in [1, 2].enumerated() {
        let img = render(scale: scale, bar: bar, ink: ink, vector: vector)
        let side = 24 * 2 * zoom   // both columns shown at the same size: 1x at 12x, 2x at 6x
        sheet.draw(img, in: CGRect(x: col * cell + 10, y: (rows.count - 1 - r) * cell + 10, width: side, height: side))
    }
}
try! NSBitmapImageRep(cgImage: sheet.makeImage()!).representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")

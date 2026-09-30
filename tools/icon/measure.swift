// Finds the artwork's rounded square: its bounds and corner radius. Run it on a new source
// image and put the numbers in make-app-icon.swift.
import CoreGraphics
import Foundation
import ImageIO

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
// Row 0 of `px` is the top of the image.
func isShape(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    return min(px[i], px[i + 1], px[i + 2]) < 200   // the artwork is dark/saturated; the surround is white
}
var minX = w, maxX = 0, minY = h, maxY = 0
for y in 0..<h { for x in 0..<w where isShape(x, y) { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
// Corner radius from the diagonal: the arc meets the diagonal at t = r(1 - 1/sqrt 2) from the corner.
func diag(_ cx: Int, _ cy: Int, _ dx: Int, _ dy: Int) -> Int {
    var t = 0
    while !isShape(cx + dx * t, cy + dy * t) { t += 1 }
    return t
}
let ts = [diag(minX, minY, 1, 1), diag(maxX, minY, -1, 1), diag(minX, maxY, 1, -1), diag(maxX, maxY, -1, -1)]
let r = Double(ts.reduce(0, +)) / 4 / (1 - 1 / 2.0.squareRoot())
print("bbox x \(minX)...\(maxX) y \(minY)...\(maxY) size \(maxX - minX + 1)x\(maxY - minY + 1)")
print("diagonal insets \(ts) -> corner radius ~\(Int(r)) px (\(String(format: "%.1f", r / Double(maxX - minX + 1) * 100))% of width)")

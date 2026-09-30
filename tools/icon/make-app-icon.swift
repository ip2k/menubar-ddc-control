// Crops the artwork's rounded square, masks it with macOS's continuous-corner icon shape (slightly
// inside the artwork's own ~19% corners, so no white survives), and places it on Apple's 1024 px
// icon grid (824 px body, 100 px margin) with the standard soft shadow.
//
//   make-app-icon <source.jpg> <out-1024.png>
import AppKit
import SwiftUI

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let art = NSImage(contentsOf: input)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
// From measure.swift on icon-source.jpg: an 820 px square at (102, 102), corner radius ~157 px.
let crop = art.cropping(to: CGRect(x: 102, y: 102, width: 820, height: 820))!

let canvas = 1024, body = 824.0, margin = 100.0
let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rect = CGRect(x: margin, y: margin, width: body, height: body)
let shape = RoundedRectangle(cornerRadius: body * 0.2237, style: .continuous).path(in: rect).cgPath

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Draw 3 px past the mask so it falls inside the artwork's anti-aliased edge.
ctx.addPath(shape)
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(crop, in: rect.insetBy(dx: -3, dy: -3))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path)")

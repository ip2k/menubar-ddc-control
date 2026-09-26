import AppKit

/// The menu bar glyph: the app icon's two circular arrows around two meshing gears, simplified
/// to read at 18 pt. Drawn as a template image (black on clear), so macOS tints it for light and
/// dark menu bars and for the highlighted state, like the system's own menu bar icons.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static let image: NSImage = {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, rect: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Menubar DDC Control"
        return image
    }()

    /// Draws in black; the template flag turns it into the menu bar's colour.
    static func draw(in ctx: CGContext, rect: CGRect) {
        let s = min(rect.width, rect.height) / 18
        let c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.setFillColor(.black)
        ctx.setStrokeColor(.black)

        // Two arrows around a ring, as in the icon: one sweeping up the left to the top and
        // pointing right, the other sweeping down the right to the bottom and pointing left.
        let radius = 7.1 * s, width = 1.5 * s
        ctx.setLineWidth(width)
        ctx.setLineCap(.butt)
        for (start, end) in [(198.0, 92.0), (18.0, -88.0)] {
            ctx.addArc(center: c, radius: radius, startAngle: rad(start), endAngle: rad(end), clockwise: true)
            ctx.strokePath()
            arrowhead(in: ctx, center: c, radius: radius, angle: end, length: 3.1 * s, halfWidth: 2.1 * s)
        }

        // Two meshing gears, each with a hub hole, rotated half a tooth apart so they interlock.
        let gearRadius = 2.9 * s, offset = 2.55 * s
        gear(in: ctx, center: CGPoint(x: c.x - offset, y: c.y), outer: gearRadius, teeth: 7, phase: 0, hole: 0.95 * s, scale: s)
        gear(in: ctx, center: CGPoint(x: c.x + offset, y: c.y), outer: gearRadius, teeth: 7, phase: .pi / 7, hole: 0.95 * s, scale: s)
    }

    private static func rad(_ degrees: Double) -> CGFloat { CGFloat(degrees * .pi / 180) }

    /// A filled triangle at `angle` on the ring, pointing clockwise along it.
    private static func arrowhead(in ctx: CGContext, center c: CGPoint, radius r: CGFloat, angle: Double,
                                  length: CGFloat, halfWidth: CGFloat) {
        let a = rad(angle)
        let base = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        let tangent = CGVector(dx: sin(a), dy: -cos(a))     // clockwise direction
        let normal = CGVector(dx: cos(a), dy: sin(a))
        ctx.move(to: CGPoint(x: base.x + tangent.dx * length, y: base.y + tangent.dy * length))
        ctx.addLine(to: CGPoint(x: base.x + normal.dx * halfWidth, y: base.y + normal.dy * halfWidth))
        ctx.addLine(to: CGPoint(x: base.x - normal.dx * halfWidth, y: base.y - normal.dy * halfWidth))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func gear(in ctx: CGContext, center c: CGPoint, outer: CGFloat, teeth: Int, phase: CGFloat,
                             hole: CGFloat, scale s: CGFloat) {
        let inner = outer - 0.95 * s
        let path = CGMutablePath()
        let step = 2 * CGFloat.pi / CGFloat(teeth)
        for i in 0..<teeth {
            let a = phase + CGFloat(i) * step
            // Each tooth: flat top over 40% of the step, root over the rest.
            let points: [(CGFloat, CGFloat)] = [
                (inner, a - step * 0.30), (outer, a - step * 0.18), (outer, a + step * 0.18), (inner, a + step * 0.30),
            ]
            for (j, (r, t)) in points.enumerated() {
                let p = CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
                if i == 0 && j == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: hole * 2, height: hole * 2))
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
    }
}

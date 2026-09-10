import SwiftUI

/// A comet that flies from where the device was to where it now claims to be.
struct TeleportArc: View {
    var from: CGPoint
    var to: CGPoint
    var progress: Double
    var tint: Color

    /// Tail length as a fraction of the whole arc.
    private let tail = 0.32

    var body: some View {
        ZStack {
            ArcShape(from: from, control: control, to: to)
                .trim(from: max(0, progress - tail), to: progress)
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0), tint, .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .shadow(color: tint.opacity(0.9), radius: 10)

            Circle()
                .fill(.white)
                .frame(width: 9, height: 9)
                .shadow(color: tint, radius: 10)
                .shadow(color: tint.opacity(0.6), radius: 22)
                .position(head)
                .opacity(progress > 0.001 && progress < 0.999 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    /// Bows the path perpendicular to the straight line, so it arcs like a flight path.
    private var control: CGPoint {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let span = max(hypot(delta.x, delta.y), 1)
        let lift = min(span * 0.3, 260)
        return CGPoint(
            x: mid.x - delta.y / span * lift,
            y: mid.y + delta.x / span * lift
        )
    }

    private var head: CGPoint {
        ArcShape.point(at: progress, from: from, control: control, to: to)
    }
}

private struct ArcShape: Shape {
    var from: CGPoint
    var control: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        return path
    }

    /// Quadratic Bézier evaluation, used to keep the glowing head on the stroke.
    static func point(at t: Double, from: CGPoint, control: CGPoint, to: CGPoint) -> CGPoint {
        let t = min(max(t, 0), 1)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x,
            y: inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y
        )
    }
}

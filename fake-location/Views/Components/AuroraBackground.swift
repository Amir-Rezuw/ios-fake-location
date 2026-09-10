import SwiftUI

/// A slow-drifting mesh gradient, masked into a vignette so it frames the map
/// instead of covering it. Recoloured by whichever destination is aimed at.
struct AuroraBackground: View {
    var palette: Palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: context.date.timeIntervalSinceReferenceDate),
                colors: colors
            )
        }
        .animation(.easeInOut(duration: 1.1), value: palette)
        .mask {
            // Stays clear well past the centre so the map underneath keeps its contrast;
            // the colour only builds up in the corners.
            RadialGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.3), location: 0.74),
                    .init(color: .black, location: 1.0),
                ],
                center: .center,
                startRadius: 60,
                endRadius: 580
            )
        }
        .blendMode(.plusLighter)
        .opacity(0.6)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var colors: [Color] {
        [
            palette.low, palette.mid, palette.low,
            palette.mid, palette.high, palette.mid,
            palette.low, palette.mid, palette.low,
        ]
    }

    /// Edge points slide only along their own edge — letting them leave it would tear
    /// a hole in the mesh — while the centre point is free to wander.
    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ phase: Double, _ rate: Double, _ amount: Float) -> Float {
            Float(sin(time * rate + phase)) * amount
        }

        return [
            SIMD2(0, 0),
            SIMD2(0.5 + wave(0.4, 0.31, 0.16), 0),
            SIMD2(1, 0),
            SIMD2(0, 0.5 + wave(1.1, 0.27, 0.14)),
            SIMD2(0.5 + wave(2.0, 0.37, 0.18), 0.5 + wave(0.7, 0.23, 0.18)),
            SIMD2(1, 0.5 + wave(2.8, 0.29, 0.14)),
            SIMD2(0, 1),
            SIMD2(0.5 + wave(3.4, 0.33, 0.16), 1),
            SIMD2(1, 1),
        ]
    }
}

import SwiftUI

/// The crosshair at screen centre marking where you're aiming.
///
/// It lifts off the map while you pan — scaling up and pulling its shadow away — and
/// settles back with a spring, which is what sells the "pin hovering over a map" read.
struct Reticle: View {
    var isAdjusting: Bool
    var isLocked: Bool
    var tint: Color

    @State private var sweep = 0.0

    var body: some View {
        ZStack {
            shadow
            halo
            dial
            core
        }
        .frame(width: 132, height: 132)
        .scaleEffect(isAdjusting ? 1.14 : 1)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: isAdjusting)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
    }

    /// Grounds the reticle to the map, and separates from it as the reticle lifts.
    private var shadow: some View {
        Ellipse()
            .fill(.black.opacity(isAdjusting ? 0.22 : 0.4))
            .frame(width: isAdjusting ? 26 : 38, height: isAdjusting ? 8 : 11)
            .blur(radius: isAdjusting ? 5 : 2.5)
            .offset(y: isAdjusting ? 46 : 34)
    }

    private var halo: some View {
        PhaseAnimator([0.0, 1.0], trigger: isLocked) { phase in
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.42 - 0.34 * phase), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 44 + 30 * phase
                    )
                )
                .scaleEffect(0.55 + 0.45 * phase)
        } animation: { _ in
            .easeOut(duration: isLocked ? 1.6 : 2.6)
        }
    }

    /// Rotating dashed ring plus four fixed ticks.
    private var dial: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    tint.opacity(0.75),
                    style: StrokeStyle(lineWidth: 1.4, dash: [2, 7], dashPhase: 0)
                )
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(sweep))

            Circle()
                .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                .frame(width: 62, height: 62)

            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 1.6, height: isAdjusting ? 13 : 9)
                    .offset(y: -40)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .shadow(color: tint.opacity(0.6), radius: 8)
    }

    private var core: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: isLocked ? 12 : 8, height: isLocked ? 12 : 8)
                .shadow(color: tint, radius: 10)

            if isLocked {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isLocked)
    }
}

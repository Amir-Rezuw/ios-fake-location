import SwiftUI

/// The commit button, which doubles as the progress indicator for the round trip
/// out to the Mac and back.
struct TeleportButton: View {
    var phase: TeleportStore.Phase
    var isEnabled: Bool
    var tint: Color
    var action: () -> Void

    @State private var sweep = 0.0
    @State private var shimmer = -1.0

    var body: some View {
        Button(action: action) {
            ZStack {
                label
                    .padding(.vertical, 19)
                    .frame(maxWidth: .infinity)
            }
            .background {
                if phase == .charging { chargingRing }
            }
            .overlay {
                if phase == .charging { shimmerSweep }
            }
        }
        .buttonStyle(SpringPress())
        .glassEffect(
            .regular.tint(glassTint).interactive(isEnabled),
            in: .capsule
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), tint.opacity(0.15), .white.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .clipShape(.capsule)
        .shadow(color: tint.opacity(isEnabled ? 0.45 : 0), radius: 22, y: 8)
        .disabled(!isEnabled || phase == .charging)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.35), value: isEnabled)
        .animation(.smooth(duration: 0.35), value: phase)
        .onChange(of: phase) { _, new in
            guard new == .charging else { return }
            sweep = 0
            shimmer = -1
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { sweep = 360 }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) { shimmer = 1.6 }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: phase == .charging)
        .sensoryFeedback(.success, trigger: phase == .arrived)
    }

    private var glassTint: Color {
        switch phase {
        case .idle: tint.opacity(0.5)
        case .charging: tint.opacity(0.7)
        case .arrived: .green.opacity(0.55)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch phase {
        case .idle:
            HStack(spacing: 10) {
                Image(systemName: "globe.europe.africa.fill")
                    .symbolEffect(.rotate, options: .nonRepeating)
                Text(isEnabled ? "Teleport" : "Agent unavailable")
            }
            .transition(.blurReplace)

        case .charging:
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .symbolEffect(.variableColor.iterative.hideInactiveLayers)
                Text("Locking on")
            }
            .transition(.blurReplace)

        case .arrived:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, options: .nonRepeating)
                Text("Arrived")
            }
            .transition(.blurReplace)
        }
    }

    /// A conic gradient rotating behind the glass while we wait for confirmation.
    private var chargingRing: some View {
        Capsule()
            .fill(
                AngularGradient(
                    colors: [.clear, tint.opacity(0.15), tint, .clear],
                    center: .center,
                    angle: .degrees(sweep)
                )
            )
            .blur(radius: 10)
    }

    private var shimmerSweep: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: proxy.size.width * 0.45)
                .offset(x: shimmer * proxy.size.width)
        }
        .clipShape(.capsule)
        .allowsHitTesting(false)
    }
}

/// Press feedback that compresses on touch-down and springs back.
struct SpringPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

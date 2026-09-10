import SwiftUI

/// Concentric rings that burst out of the reticle the moment a teleport lands.
///
/// One animated value drives every ring, each offset a little further along it, which
/// staggers them without needing separate animations to stay in sync.
struct Shockwave: View {
    var isActive: Bool
    var tint: Color

    private let ringCount = 4

    @State private var wave = 0.0

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { index in
                let progress = ringProgress(index)

                Circle()
                    .strokeBorder(
                        tint.opacity(0.9 * (1 - progress)),
                        lineWidth: 2.5 * (1 - progress) + 0.5
                    )
                    .frame(width: 90, height: 90)
                    .scaleEffect(0.35 + progress * 3.4)
                    .blur(radius: progress * 2)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            guard active else { return }
            wave = 0
            withAnimation(.easeOut(duration: 1.5)) { wave = 1 }
        }
    }

    private func ringProgress(_ index: Int) -> Double {
        let delay = Double(index) * 0.11
        return min(max((wave - delay) / (1 - delay), 0), 1)
    }
}

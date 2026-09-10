import SwiftUI

/// The name and coordinates of whatever is under the reticle.
struct CoordinateReadout: View {
    var place: Place
    var isPinned: Bool
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                ZStack {
                    Text(place.name)
                        .id(place.name)
                        .transition(.blurReplace)
                }
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(tint)
                        .symbolEffect(.bounce, options: .nonRepeating)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(place.region)
                .id(place.region)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .transition(.blurReplace)

            HStack(spacing: 10) {
                axis(place.latitude, positive: "N", negative: "S")
                axis(place.longitude, positive: "E", negative: "W")
            }
            .padding(.top, 5)
        }
        .foregroundStyle(.white)
        .animation(.smooth(duration: 0.4), value: place.name)
        .animation(.smooth(duration: 0.4), value: place.region)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isPinned)
    }

    /// Digits roll rather than cut, so panning the map reads as a continuous change.
    private func axis(_ value: Double, positive: String, negative: String) -> some View {
        HStack(spacing: 0) {
            Text(abs(value), format: .number.precision(.fractionLength(4)))
                .contentTransition(.numericText())
            Text("°\(value >= 0 ? positive : negative)")
        }
        .font(.system(.footnote, design: .monospaced, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }
}

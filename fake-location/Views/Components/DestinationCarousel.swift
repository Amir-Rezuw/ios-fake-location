import SwiftUI

/// Horizontally scrolling shortlist of destinations.
///
/// Cards rotate away from the centre as they scroll, so the row reads as a curved
/// carousel rather than a flat list.
struct DestinationCarousel: View {
    var places: [Place]
    var selection: Place
    var onPick: (Place) -> Void

    @State private var scrolled: String?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(places, id: \.name) { place in
                    DestinationCard(place: place, isSelected: place.name == selection.name) {
                        onPick(place)
                    }
                    .containerRelativeFrame(.horizontal, count: 5, span: 2, spacing: 12)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.88)
                            .opacity(phase.isIdentity ? 1 : 0.6)
                            .blur(radius: phase.isIdentity ? 0 : 1.6)
                            .rotation3DEffect(
                                .degrees(phase.value * -26),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.42
                            )
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolled, anchor: .center)
        .frame(height: 108)
        .onAppear { scrolled = selection.name }
        .onChange(of: selection.name) { _, name in
            // A dropped pin isn't in the list, so leave the carousel where it is.
            guard places.contains(where: { $0.name == name }) else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { scrolled = name }
        }
    }
}

private struct DestinationCard: View {
    var place: Place
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "location.north.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(bearing))

                Spacer(minLength: 6)

                Text(place.name)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(place.region)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background {
                LinearGradient(
                    colors: [place.palette.mid.opacity(0.75), place.palette.low.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected ? place.palette.high : .white.opacity(0.12),
                        lineWidth: isSelected ? 1.8 : 0.8
                    )
            }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .shadow(
                color: isSelected ? place.palette.high.opacity(0.5) : .black.opacity(0.35),
                radius: isSelected ? 14 : 6,
                y: 4
            )
            .scaleEffect(isSelected ? 1.03 : 1)
        }
        .buttonStyle(CardPress())
        .foregroundStyle(.white)
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: isSelected)
    }

    /// Points the little arrow somewhere consistent per city, purely as decoration.
    private var bearing: Double {
        (place.longitude + 180).truncatingRemainder(dividingBy: 360)
    }
}

private struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

import SwiftUI

/// Everything you touch: what's aimed at, the shortlist, and the commit button.
struct ControlDeck: View {
    @Environment(TeleportStore.self) private var store

    var onSearch: () -> Void

    @Namespace private var glass

    var body: some View {
        VStack(spacing: 14) {
            DestinationCarousel(
                places: shortlist,
                selection: store.target,
                onPick: { store.aim(at: $0) }
            )

            deck
        }
    }

    /// Recently used places float to the front of the shortlist.
    private var shortlist: [Place] {
        let recentNames = Set(store.history.map(\.name))
        return store.history + Place.featured.filter { !recentNames.contains($0.name) }
    }

    private var deck: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CoordinateReadout(
                    place: store.target,
                    isPinned: store.pinned?.coordinate.isEssentially(store.target.coordinate) == true,
                    tint: store.target.palette.high
                )

                Spacer(minLength: 0)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 10) {
                        GlassIconButton(symbol: "magnifyingglass", action: onSearch)
                            .glassEffectID("search", in: glass)

                        if store.device.coordinate != nil {
                            GlassIconButton(symbol: "location.fill") {
                                store.aimAtDevice()
                            }
                            .glassEffectID("locate", in: glass)
                            .transition(.scale.combined(with: .opacity))
                        }

                        if store.isSpoofing {
                            GlassIconButton(symbol: "pin.slash.fill", tint: .orange) {
                                store.release()
                            }
                            .glassEffectID("release", in: glass)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }

            TeleportButton(
                phase: store.phase,
                isEnabled: store.link.canTeleport,
                tint: store.target.palette.high
            ) {
                store.teleport()
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: store.isSpoofing)
    }
}

struct GlassIconButton: View {
    var symbol: String
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
        }
        .buttonStyle(SpringPress())
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

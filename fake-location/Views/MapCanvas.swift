import MapKit
import SwiftUI

/// The map, the reticle over its centre, and the arrival effects drawn on top.
struct MapCanvas: View {
    @Environment(TeleportStore.self) private var store

    @State private var camera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: Place.featured[0].coordinate, distance: 40_000)
    )
    @State private var isAdjusting = false
    /// Set while the camera is animating to a deliberate pick, so those camera
    /// updates aren't mistaken for the user panning.
    @State private var isFlying = false
    @State private var arcProgress = 0.0
    @State private var settle: Task<Void, Never>?

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()

                if let pinned = store.pinned {
                    Annotation(pinned.name, coordinate: pinned.coordinate) {
                        PinnedMarker(tint: store.target.palette.high)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.airport, .publicTransport])))
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .continuous) { context in
                guard !isFlying else { return }
                store.aimFreely(to: context.camera.centerCoordinate)
                markAdjusting()
            }
            .overlay {
                arc(in: proxy)
            }
            .overlay {
                ZStack {
                    Shockwave(isActive: store.phase == .arrived, tint: store.target.palette.high)
                    Reticle(
                        isAdjusting: isAdjusting,
                        isLocked: store.isSpoofing,
                        tint: store.target.palette.high
                    )
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: store.flightToken) { _, _ in
            fly(to: store.target)
        }
        .onChange(of: store.phase) { _, phase in
            guard phase == .arrived else { return }
            arcProgress = 0
            withAnimation(.easeInOut(duration: 1.5)) { arcProgress = 1 }
        }
    }

    @ViewBuilder
    private func arc(in proxy: MapProxy) -> some View {
        if store.phase == .arrived,
           let origin = store.departure,
           let start = proxy.convert(origin, to: .local),
           let end = proxy.convert(store.target.coordinate, to: .local) {
            TeleportArc(
                from: clamp(start, near: end),
                to: end,
                progress: arcProgress,
                tint: store.target.palette.high
            )
        }
    }

    /// A departure on the far side of the world projects to a point thousands of
    /// screens away; pull it in so the comet still enters from a sensible direction.
    private func clamp(_ point: CGPoint, near anchor: CGPoint) -> CGPoint {
        let delta = CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)
        let span = hypot(delta.x, delta.y)
        let limit: CGFloat = 900
        guard span > limit else { return point }
        return CGPoint(
            x: anchor.x + delta.x / span * limit,
            y: anchor.y + delta.y / span * limit
        )
    }

    private func fly(to place: Place) {
        isFlying = true
        withAnimation(.easeInOut(duration: 1.0)) {
            camera = .camera(MapCamera(centerCoordinate: place.coordinate, distance: 40_000))
        }
        Task {
            try? await Task.sleep(for: .seconds(1.05))
            isFlying = false
        }
    }

    /// Lifts the reticle while the map moves, dropping it once movement stops.
    private func markAdjusting() {
        if !isAdjusting { isAdjusting = true }
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            isAdjusting = false
        }
    }
}

/// Marks the coordinate the device is actually reporting right now.
private struct PinnedMarker: View {
    var tint: Color

    var body: some View {
        PhaseAnimator([0.0, 1.0]) { phase in
            ZStack {
                Circle()
                    .fill(tint.opacity(0.35 * (1 - phase)))
                    .frame(width: 26 + 34 * phase, height: 26 + 34 * phase)

                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().fill(tint).frame(width: 7, height: 7)
                    }
                    .shadow(color: tint, radius: 8)
            }
        } animation: { _ in
            .easeOut(duration: 1.8)
        }
    }
}

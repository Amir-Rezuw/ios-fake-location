import SwiftUI

struct RootView: View {
    @Environment(TeleportStore.self) private var store

    @State private var isSearching = false

    var body: some View {
        ZStack {
            MapCanvas()

            AuroraBackground(palette: store.target.palette)

            VStack(spacing: 0) {
                StatusPill(link: store.link)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                ControlDeck { isSearching = true }
                    .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isSearching) {
            SearchSheet()
        }
    }
}

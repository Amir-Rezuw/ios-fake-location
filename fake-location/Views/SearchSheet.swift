import SwiftUI

/// Search anywhere in the world, or jump back to somewhere you've already been.
struct SearchSheet: View {
    @Environment(TeleportStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isFocused: Bool
    @State private var resolving: UUID?

    var body: some View {
        VStack(spacing: 0) {
            field
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.search.query.isEmpty {
                        section("Recent", places: store.history)
                        section("Featured", places: Place.featured)
                    } else {
                        ForEach(Array(store.search.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionRow(
                                title: suggestion.title,
                                subtitle: suggestion.subtitle,
                                isResolving: resolving == suggestion.id
                            ) {
                                pick(suggestion)
                            }
                            .transition(
                                .asymmetric(
                                    insertion: .offset(y: 14).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                            // A small per-row delay makes the list assemble rather than snap.
                            .animation(
                                .spring(response: 0.38, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.035),
                                value: store.search.suggestions.count
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            LinearGradient(
                colors: [store.target.palette.low.opacity(0.9), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .presentationDetents([.large])
        .presentationBackground(.black.opacity(0.4))
        .onAppear { isFocused = true }
        .onDisappear { store.search.clear() }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search for a city or place", text: Binding(
                get: { store.search.query },
                set: { store.search.query = $0 }
            ))
            .focused($isFocused)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .autocorrectionDisabled()

            if !store.search.query.isEmpty {
                Button {
                    store.search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.system(.body, design: .rounded))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.snappy, value: store.search.query.isEmpty)
    }

    @ViewBuilder
    private func section(_ title: String, places: [Place]) -> some View {
        if !places.isEmpty {
            HStack {
                Text(title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 2)

            ForEach(places) { place in
                SuggestionRow(
                    title: place.name,
                    subtitle: place.region,
                    isResolving: false
                ) {
                    store.aim(at: place)
                    dismiss()
                }
            }
        }
    }

    private func pick(_ suggestion: PlaceSearch.Suggestion) {
        resolving = suggestion.id
        Task {
            defer { resolving = nil }
            guard let place = await store.search.resolve(suggestion) else { return }
            store.aim(at: place)
            dismiss()
        }
    }
}

private struct SuggestionRow: View {
    var title: String
    var subtitle: String
    var isResolving: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CardPress())
        .foregroundStyle(.white)
    }
}

private struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

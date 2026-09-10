import SwiftUI

/// Live health of the whole chain, collapsed into a pill that expands into a
/// breakdown when tapped.
///
/// Four things have to be true before a teleport can work, and any of them can be the
/// broken one, so the expanded view names each link and what to do about it.
struct StatusPill: View {
    var link: AgentLink

    @State private var isExpanded = false
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 10) {
                pill

                if isExpanded {
                    breakdown
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                        .glassEffectID("breakdown", in: glass)
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: isExpanded)
    }

    private var pill: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: headlineSymbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(headlineColor)
                    .symbolEffect(.variableColor.iterative, isActive: isBusy)

                Text(headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassEffect(.regular.tint(headlineColor.opacity(0.22)).interactive(), in: .capsule)
        .glassEffectID("pill", in: glass)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().overlay(.white.opacity(0.08))
                }
                ChainRow(row: row)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 296)
    }

    // MARK: - Derived state

    private var headline: String {
        switch link.linkState {
        case .searching: "Looking for your Mac"
        case .connecting: "Connecting"
        case .linked: link.status.headline
        }
    }

    private var headlineSymbol: String {
        switch link.linkState {
        case .searching: "wifi.exclamationmark"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .linked: link.status.symbol
        }
    }

    private var headlineColor: Color {
        guard link.linkState == .linked else { return .orange }
        switch link.status.stage {
        case .spoofing: return .green
        case .ready: return .cyan
        case .connecting: return .yellow
        case .tunnelOffline, .noDevice, .error: return .orange
        }
    }

    private var isBusy: Bool {
        link.linkState != .linked || link.status.stage == .connecting
    }

    private var rows: [ChainRow.Model] {
        let agentUp = link.linkState == .linked
        let stage = link.status.stage
        let tunnelUp = agentUp && stage != .tunnelOffline
        let deviceUp = tunnelUp && stage != .noDevice && stage != .error

        return [
            ChainRow.Model(
                title: "Mac agent",
                detail: agentUp
                    ? "Connected over the local network"
                    : "Start teleportd.py on your Mac, on this Wi-Fi",
                health: agentUp ? .ok : (link.linkState == .connecting ? .pending : .down)
            ),
            ChainRow.Model(
                title: "Developer tunnel",
                detail: tunnelUp
                    ? "Open"
                    : "Run: sudo pymobiledevice3 remote tunneld",
                health: !agentUp ? .idle : (tunnelUp ? .ok : .down)
            ),
            ChainRow.Model(
                title: link.status.device ?? "This iPhone",
                detail: deviceUp
                    ? "Trusted and reachable"
                    : (stage == .error
                        ? (link.status.detail ?? "The device dropped off the tunnel")
                        : "Connect by USB and trust this Mac"),
                health: !tunnelUp ? .idle : (deviceUp ? .ok : .down)
            ),
            ChainRow.Model(
                // Only echo the agent's own detail once the rows above are satisfied,
                // otherwise it just repeats whichever hint they're already showing.
                title: "System location",
                detail: stage == .spoofing
                    ? "Overridden for every app"
                    : (deviceUp ? (link.status.detail ?? "Real GPS in use") : "Real GPS in use"),
                health: stage == .spoofing ? .ok : .idle
            ),
        ]
    }
}

private struct ChainRow: View {
    enum Health {
        case ok, pending, down, idle
    }

    struct Model {
        var title: String
        var detail: String
        var health: Health
    }

    var row: Model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: row.health == .pending)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var symbol: String {
        switch row.health {
        case .ok: "checkmark.circle.fill"
        case .pending: "circle.dotted"
        case .down: "exclamationmark.circle.fill"
        case .idle: "circle"
        }
    }

    private var color: Color {
        switch row.health {
        case .ok: .green
        case .pending: .yellow
        case .down: .orange
        case .idle: .secondary
        }
    }
}

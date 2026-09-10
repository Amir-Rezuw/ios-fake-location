import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "com.amirrezajamali.teleport", category: "AgentLink")

/// One TCP channel to the Mac agent, exposed as a stream of events.
///
/// `NWConnection` serialises every callback onto the queue it was started with, and the
/// only state these callbacks touch is the stream continuation — the read buffer is
/// threaded through `receive` as a parameter rather than stored — so there is nothing
/// here for two threads to race over.
private final class AgentChannel: @unchecked Sendable {
    enum Event {
        case ready
        case line(Data)
        case ended
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.amirrezajamali.teleport.agent-channel")

    init(endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: .tcp)
    }

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.yield(.ready)
                case .failed, .cancelled:
                    continuation.yield(.ended)
                    continuation.finish()
                default:
                    break
                }
            }
            continuation.onTermination = { [connection] _ in
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
            connection.start(queue: queue)
            receive(buffer: Data(), into: continuation)
        }
    }

    private func receive(buffer: Data, into continuation: AsyncStream<Event>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] chunk, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty { continuation.yield(.line(Data(line))) }
            }

            if isComplete || error != nil {
                continuation.yield(.ended)
                continuation.finish()
                return
            }
            receive(buffer: buffer, into: continuation)
        }
    }

    func send(_ payload: Data) {
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error { log.error("send failed: \(error.localizedDescription)") }
        })
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}

/// Discovers the Mac agent over Bonjour and keeps a connection to it alive.
@Observable
final class AgentLink {
    enum LinkState: Equatable {
        /// No agent has been seen on the network yet.
        case searching
        case connecting
        case linked
    }

    private(set) var linkState: LinkState = .searching
    /// Last status reported by the agent. Only meaningful while `linkState == .linked`.
    private(set) var status = Teleport.Status(stage: .connecting)

    private var discovered: [NWEndpoint] = []
    private var channel: AgentChannel?
    private var tasks: [Task<Void, Never>] = []

    /// True when the whole chain — app, agent, tunnel, device — is able to teleport.
    var canTeleport: Bool {
        linkState == .linked && status.acceptsCommands
    }

    func activate() {
        guard tasks.isEmpty else { return }
        tasks.append(Task { await self.trackAgents() })
        tasks.append(Task { await self.keepConnected() })
    }

    func deactivate() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        channel?.cancel()
        channel = nil
        linkState = .searching
    }

    func send(_ command: Teleport.Command) {
        guard let channel, var payload = try? JSONEncoder().encode(command) else { return }
        payload.append(UInt8(ascii: "\n"))
        channel.send(payload)
    }

    // MARK: - Discovery

    private func trackAgents() async {
        for await endpoints in Self.browse() {
            discovered = endpoints
        }
    }

    private static func browse() -> AsyncStream<[NWEndpoint]> {
        AsyncStream { continuation in
            let browser = NWBrowser(
                for: .bonjour(type: Teleport.serviceType, domain: nil),
                using: .tcp
            )
            browser.browseResultsChangedHandler = { results, _ in
                continuation.yield(results.map(\.endpoint))
            }
            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    log.error("browser failed: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Connection

    /// Connects to a discovered agent and reconnects for as long as the task lives.
    private func keepConnected() async {
        while !Task.isCancelled {
            guard let endpoint = discovered.first else {
                linkState = .searching
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            linkState = .connecting
            await pump(endpoint)

            guard !Task.isCancelled else { return }
            // Stay on "connecting" while the agent is still advertising — it may just be
            // restarting — so the status doesn't flap once per retry.
            linkState = discovered.isEmpty ? .searching : .connecting
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Runs one connection to completion, publishing every status it reports.
    private func pump(_ endpoint: NWEndpoint) async {
        let channel = AgentChannel(endpoint: endpoint)
        self.channel = channel
        defer {
            channel.cancel()
            if self.channel === channel { self.channel = nil }
        }

        for await event in channel.events() {
            switch event {
            case .ready:
                linkState = .linked
                send(.status)
            case .line(let data):
                guard let update = try? JSONDecoder().decode(Teleport.Status.self, from: data) else {
                    log.error("undecodable status: \(String(decoding: data, as: UTF8.self))")
                    continue
                }
                linkState = .linked
                status = update
            case .ended:
                return
            }
        }
    }
}

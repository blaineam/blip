import Foundation
import Network

/// TCP server that listens on localhost and serves HelperSnapshots to the main app.
/// Uses TOTP authentication to prevent unauthorized access.
final class HelperServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.blainemiller.BlipHelper.server")
    private let daemon = HelperDaemon()
    private var latestSnapshot: HelperSnapshot?
    private let pollInterval: TimeInterval = 2.0

    /// Start the TCP server on a random localhost port.
    /// Returns the port number, or nil on failure.
    func start() -> UInt16? {
        // Configure TCP listener on loopback only
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

        do {
            listener = try NWListener(using: params)
        } catch {
            fputs("BlipHelper: Failed to create listener: \(error)\n", stderr)
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var assignedPort: UInt16?

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                assignedPort = self.listener?.port?.rawValue
                semaphore.signal()
            case .failed(let error):
                fputs("BlipHelper: Listener failed: \(error)\n", stderr)
                semaphore.signal()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)

        // Wait up to 5 seconds for the listener to be ready
        _ = semaphore.wait(timeout: .now() + 5)

        guard let port = assignedPort else { return nil }

        // Write port to shared container for the main app to discover
        writePortFile(port)

        // Start polling daemon
        startPolling()

        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
        // Clean up port file
        try? FileManager.default.removeItem(at: HelperConstants.portFileURL)
    }

    // MARK: - Port File

    private func writePortFile(_ port: UInt16) {
        let url = HelperConstants.portFileURL
        // Ensure parent directory exists
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? String(port).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Polling

    private func startPolling() {
        queue.async { [weak self] in
            self?.pollLoop()
        }
    }

    private func pollLoop() {
        guard listener != nil else { return }
        latestSnapshot = daemon.poll()
        queue.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            self?.pollLoop()
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeader(on: connection)
    }

    /// Read the 4-byte length header.
    private func receiveHeader(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4 else {
                connection.cancel()
                return
            }
            guard let length = MessageFraming.decodeLength(from: data), length > 0, length < 65536 else {
                connection.cancel()
                return
            }
            self.receiveBody(length: Int(length), on: connection)
        }
    }

    /// Read the JSON body and process the request.
    private func receiveBody(length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self, let data else {
                connection.cancel()
                return
            }
            self.processRequest(data, on: connection)
        }
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        guard let request = try? JSONDecoder().decode(HelperRequest.self, from: data) else {
            sendError("Invalid request", on: connection)
            return
        }

        // Validate TOTP token
        guard TOTP.validate(request.token) else {
            sendError("Authentication failed", on: connection)
            return
        }

        switch request.type {
        case "poll":
            guard let snapshot = latestSnapshot else {
                sendError("No data available yet", on: connection)
                return
            }
            let response = HelperResponse(
                type: "snapshot",
                token: TOTP.generate(),
                data: snapshot,
                message: nil
            )
            sendResponse(response, on: connection)

        default:
            sendError("Unknown request type", on: connection)
        }
    }

    private func sendResponse(_ response: HelperResponse, on connection: NWConnection) {
        guard let frame = try? MessageFraming.encode(response) else {
            connection.cancel()
            return
        }
        connection.send(content: frame, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendError(_ message: String, on connection: NWConnection) {
        let response = HelperResponse(type: "error", token: nil, data: nil, message: message)
        sendResponse(response, on: connection)
    }
}

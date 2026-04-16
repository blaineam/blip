import Foundation
import Network

/// TCP client that connects to BlipHelper to fetch privileged system data.
/// Used by the sandboxed MAS version; the direct-download version can
/// also use it as a fallback if in-process monitors fail.
@MainActor
final class HelperClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var latestSnapshot: HelperSnapshot?

    private let queue = DispatchQueue(label: "com.blainemiller.Blip.helperClient")
    private var helperPort: UInt16?

    /// Attempt to read the helper's port file and fetch a snapshot.
    func poll() async {
        // Discover port if not yet known or if connection failed last time
        if helperPort == nil {
            helperPort = readPortFile()
        }
        guard let port = helperPort else {
            await MainActor.run {
                isConnected = false
                latestSnapshot = nil
            }
            return
        }

        let snapshot = await fetchSnapshot(port: port)
        await MainActor.run {
            if let snapshot {
                isConnected = true
                latestSnapshot = snapshot
            } else {
                // Port may be stale — re-read on next poll
                isConnected = false
                helperPort = nil
            }
        }
    }

    /// Check if the helper appears to be installed.
    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperConstants.portFileURL.path)
    }

    // MARK: - Port Discovery

    private func readPortFile() -> UInt16? {
        guard let contents = try? String(contentsOf: HelperConstants.portFileURL, encoding: .utf8),
              let port = UInt16(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
              port > 0 else {
            return nil
        }
        return port
    }

    // MARK: - TCP Request

    private func fetchSnapshot(port: UInt16) async -> HelperSnapshot? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )

            var didResume = false

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.sendRequest(on: connection) { snapshot in
                        if !didResume {
                            didResume = true
                            continuation.resume(returning: snapshot)
                        }
                        connection.cancel()
                    }
                case .failed, .cancelled:
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout after 3 seconds
            queue.asyncAfter(deadline: .now() + 3) {
                if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                    connection.cancel()
                }
            }
        }
    }

    private func sendRequest(on connection: NWConnection, completion: @escaping (HelperSnapshot?) -> Void) {
        let request = HelperRequest(type: "poll", token: TOTP.generate())
        guard let frame = try? MessageFraming.encode(request) else {
            completion(nil)
            return
        }

        connection.send(content: frame, completion: .contentProcessed { error in
            guard error == nil else {
                completion(nil)
                return
            }
            self.receiveResponse(on: connection, completion: completion)
        })
    }

    private func receiveResponse(on connection: NWConnection, completion: @escaping (HelperSnapshot?) -> Void) {
        // Read 4-byte length header
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
            guard let data, data.count == 4,
                  let length = MessageFraming.decodeLength(from: data),
                  length > 0, length < 1_048_576 else {
                completion(nil)
                return
            }
            // Read response body
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { bodyData, _, _, error in
                guard let bodyData,
                      let response = try? JSONDecoder().decode(HelperResponse.self, from: bodyData),
                      response.type == "snapshot",
                      let token = response.token,
                      TOTP.validate(token) else {
                    completion(nil)
                    return
                }
                completion(response.data)
            }
        }
    }
}

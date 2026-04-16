import Foundation
import Network

/// TCP client that connects to BlipHelper to fetch privileged system data.
/// Used by the sandboxed MAS version; the direct-download version skips
/// this entirely (isSandboxed check in SystemMonitor).
///
/// Networking runs on a dedicated dispatch queue. Results are published
/// on @MainActor via the async poll() entry point.
final class HelperClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.blainemiller.Blip.helperClient")
    private var _isConnected = false
    private var _latestSnapshot: HelperSnapshot?
    private var helperPort: UInt16?

    @MainActor var isConnected: Bool { _isConnected }
    @MainActor var latestSnapshot: HelperSnapshot? { _latestSnapshot }

    /// Check if the helper appears to be installed.
    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperConstants.portFileURL.path)
    }

    /// Attempt to read the helper's port file and fetch a snapshot.
    func poll() async {
        let snapshot = await withCheckedContinuation { (continuation: CheckedContinuation<HelperSnapshot?, Never>) in
            queue.async { [self] in
                let result = self.fetchSnapshotSync()
                continuation.resume(returning: result)
            }
        }
        await MainActor.run {
            if let snapshot {
                _isConnected = true
                _latestSnapshot = snapshot
            } else {
                _isConnected = false
                helperPort = nil
            }
        }
    }

    // MARK: - Synchronous TCP (runs on background queue)

    private func fetchSnapshotSync() -> HelperSnapshot? {
        // Discover port
        if helperPort == nil {
            helperPort = readPortFile()
        }
        guard let port = helperPort else { return nil }

        // Open TCP socket to localhost
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        // 3 second timeout for send and receive
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        // Send request
        let request = HelperRequest(type: "poll", token: TOTP.generate())
        guard let frame = try? MessageFraming.encode(request) else { return nil }
        let sent = frame.withUnsafeBytes { ptr in
            send(sock, ptr.baseAddress!, ptr.count, 0)
        }
        guard sent == frame.count else { return nil }

        // Read 4-byte length header
        var headerBuf = [UInt8](repeating: 0, count: 4)
        let headerRead = recv(sock, &headerBuf, 4, MSG_WAITALL)
        guard headerRead == 4 else { return nil }

        let length = MessageFraming.decodeLength(from: Data(headerBuf))
        guard let length, length > 0, length < 1_048_576 else { return nil }

        // Read response body
        var bodyBuf = [UInt8](repeating: 0, count: Int(length))
        let bodyRead = recv(sock, &bodyBuf, Int(length), MSG_WAITALL)
        guard bodyRead == Int(length) else { return nil }

        // Decode
        let bodyData = Data(bodyBuf)
        guard let response = try? JSONDecoder().decode(HelperResponse.self, from: bodyData),
              response.type == "snapshot",
              let token = response.token,
              TOTP.validate(token) else {
            return nil
        }
        return response.data
    }

    private func readPortFile() -> UInt16? {
        guard let contents = try? String(contentsOf: HelperConstants.portFileURL, encoding: .utf8),
              let port = UInt16(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
              port > 0 else {
            return nil
        }
        return port
    }
}

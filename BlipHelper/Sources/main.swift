import Foundation

// MARK: - BlipHelper Entry Point
//
// Lightweight LaunchAgent daemon that polls privileged system APIs
// (SMC, IOKit, proc_*) and serves the data over a local TCP socket.
// The sandboxed MAS version of Blip connects to this helper to
// display fan speeds, temperatures, GPU utilization, disk I/O,
// battery health, and process lists.

let server = HelperServer()

// Handle termination gracefully
let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN) // Let dispatch source handle it
signalSource.setEventHandler {
    server.stop()
    SMC.close()
    exit(0)
}
signalSource.resume()

let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
intSource.setEventHandler {
    server.stop()
    SMC.close()
    exit(0)
}
intSource.resume()

// Start the server
guard let port = server.start() else {
    fputs("BlipHelper: Failed to start server\n", stderr)
    exit(1)
}

fputs("BlipHelper: Listening on 127.0.0.1:\(port)\n", stderr)

// Run forever
dispatchMain()

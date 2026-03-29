import Foundation

package final class SignalMonitor {
    private var sources: [DispatchSourceSignal] = []
    package private(set) var terminationRequested = false

    package init() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler { [weak self] in
                self?.terminationRequested = true
            }
            source.resume()
            sources.append(source)
        }
    }

    package func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }
}

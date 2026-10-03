import Foundation

// Phone side of the sample watch app (watch-apps/sample). Answers the {"t":"hello"} message of any watch app;
// use it as a starting point for your own feature.
@MainActor
final class HelloFeature: WatchFeature {
    private weak var host: WatchFeatureHost?

    // Empty: sees messages from every package, handles only "hello"
    var watchPackages: [String] { [] }

    func attach(to host: WatchFeatureHost) {
        self.host = host
    }

    func handle(_ message: [String: Any], from package: String) async -> Bool {
        guard message["t"] as? String == "hello", let bridge = host?.bridge(for: package) else { return false }
        let time = Date().formatted(date: .omitted, time: .shortened)
        bridge.send(["t": "hello", "s": L("Hello from the iPhone 👋 \(time)", "iPhone'dan selam 👋 \(time)")])
        host?.log(.info, "⌚ \(package): hello")
        return true
    }
}

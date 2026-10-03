import Foundation

// JSON messaging with an app on the watch (Wear Engine P2P, service 0x34).
// Watch side: watch-apps/sample/entry/src/main/js/default/common/bridge.js
// Note: adding "supportLists" to the watch app's config.json freezes the app at launch; messaging works without it.
@MainActor
final class WatchAppBridge {
    // Watch apps address their messages to this package: the iPhone app's bundle ID
    // (on the watch side build-watch-app.sh writes it in place of __HUASIDELOAD_PHONE_PACKAGE__)
    static var phonePackage: String { Bundle.main.bundleIdentifier ?? "huasideload" }
    // Arbitrary, but must match on both sides (bridge.js PHONE_FINGERPRINT)
    static let phoneFingerprint = "CA612C488CBB19EE1601EAFFFE084ED6AC674AF264A861D9101CF1A3A191693E"

    let watchPackage: String
    // appverify GetAppid: package + "_" + public key of the developer certificate (computed by WatchAppCatalog)
    private let watchFingerprint: String

    // Wear Engine recommends at most 1 KB per message
    static let maxMessageBytes = 1000

    private let session: HuaweiSession
    private let log: (LogKind, String) -> Void
    private var queue: Task<Void, Never>?
    private(set) var lastContact: Date?

    var onMessage: (([String: Any]) -> Void)?

    init(session: HuaweiSession, watchPackage: String, watchFingerprint: String, log: @escaping (LogKind, String) -> Void) {
        self.session = session
        self.watchPackage = watchPackage
        self.watchFingerprint = watchFingerprint
        self.log = log
    }

    var isAppActive: Bool {
        guard let lastContact else { return false }
        return Date().timeIntervalSince(lastContact) < 300
    }

    func reset() {
        queue?.cancel()
        queue = nil
        lastContact = nil
    }

    func receive(from source: String, data: [UInt8]) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(data)) as? [String: Any], json["t"] is String else {
            log(.error, L("Unreadable message from a watch app: ", "Saat uygulamasından anlaşılmayan mesaj: ") + String(decoding: data.prefix(120), as: UTF8.self))
            return
        }
        lastContact = Date()
        onMessage?(json)
    }

    // Messages go one at a time, each after the previous one was acknowledged
    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        if data.count > Self.maxMessageBytes {
            log(.error, L("Watch app message is large: \(data.count) bytes (\(message["t"] ?? "?"))", "Saat uygulaması mesajı büyük: \(data.count) bayt (\(message["t"] ?? "?"))"))
        }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.session.isPaired else { return }
            await self.deliver(Array(data), type: message["t"] as? String ?? "?")
        }
    }

    // Multi-part data (e.g. a screen frame): the first (start) and the last (end) message go in order, the ones in between
    // `parallel` at a time. Waiting for acknowledgements overlaps, so the whole thing arrives much faster. Returns the number of failures.
    func sendBatch(_ messages: [[String: Any]], parallel: Int = 3) async -> Int {
        await queue?.value
        guard !Task.isCancelled else { return messages.count }
        let encoded = messages.compactMap { message -> ([UInt8], String)? in
            guard let data = try? JSONSerialization.data(withJSONObject: message) else { return nil }
            return (Array(data), message["t"] as? String ?? "?")
        }
        guard let first = encoded.first, encoded.count >= 2 else {
            for item in encoded { if !(await deliver(item.0, type: item.1)) { return 1 } }
            return 0
        }
        var failures = await deliver(first.0, type: first.1) ? 0 : 1
        let middle = Array(encoded.dropFirst().dropLast())
        var index = 0
        while index < middle.count {
            guard !Task.isCancelled else { return failures + middle.count - index + 1 }
            let chunk = middle[index..<min(index + parallel, middle.count)]
            await withTaskGroup(of: Bool.self) { group in
                for item in chunk {
                    group.addTask { await self.deliver(item.0, type: item.1) }
                }
                for await ok in group where !ok { failures += 1 }
            }
            index += parallel
        }
        if Task.isCancelled { return failures + 1 }
        if let last = encoded.last, !(await deliver(last.0, type: last.1)) { failures += 1 }
        return failures
    }

    // Waits until everything queued has been delivered
    func flush() async {
        await queue?.value
    }

    @discardableResult
    private func deliver(_ data: [UInt8], type: String) async -> Bool {
        do {
            let reply = try await session.p2p(kind: P2P.Kind.data, source: Self.phonePackage, destination: watchPackage,
                                              sourceFingerprint: Self.phoneFingerprint, destinationFingerprint: watchFingerprint,
                                              data: data)
            if let code = reply.code, code != P2P.Code.ok {
                log(.error, String(format: L("The watch app refused message '%@': 0x%X", "Saat uygulaması '%@' mesajını reddetti: 0x%X"), type, code))
                return false
            }
            return true
        } catch {
            log(.error, L("Message '\(type)' did not reach the watch app: \(error)", "Saat uygulamasına '\(type)' gitmedi: \(error)"))
            return false
        }
    }
}

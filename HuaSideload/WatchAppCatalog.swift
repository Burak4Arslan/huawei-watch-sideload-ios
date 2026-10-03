import Foundation
import Security

// Signed watch apps bundled inside the iPhone app (WatchApps/*.bin).
// tools/build-watch-app.sh writes every app there as "<app name>.bin"; no code per app is needed.
struct BundledWatchApp: Identifiable {
    var id: String { package }
    let name: String
    let package: String
    let version: String
    let data: [UInt8]
    // Identity needed for P2P messaging with the watch app (appverify GetAppid)
    let fingerprint: String?
}

enum WatchAppCatalog {
    static let all: [BundledWatchApp] = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "bin", subdirectory: nil) ?? []
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return parse([UInt8](data), name: url.deletingPathExtension().lastPathComponent)
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()

    static func app(for package: String) -> BundledWatchApp? {
        all.first { $0.package == package }
    }

    // MARK: - .bin format (Gadgetbridge HuaweiBinAppParser)
    // 0xBE, [length BE32][package], then files: [name][path][length BE64][content], signature block at the end

    static func parse(_ bytes: [UInt8], name: String) -> BundledWatchApp? {
        guard bytes.count > 5, bytes[0] == 0xBE else { return nil }
        var offset = 1
        guard let package = readString(bytes, &offset) else { return nil }
        let signLength = signatureLength(bytes)
        var version = ""
        while bytes.count - offset > signLength {
            guard let fileName = readString(bytes, &offset), let path = readString(bytes, &offset, allowEmpty: true),
                  offset + 8 <= bytes.count else { break }
            let length = bytes[offset..<(offset + 8)].reduce(0) { $0 << 8 | Int($1) }
            offset += 8
            guard length >= 0, offset + length <= bytes.count else { break }
            if fileName == "config.json", path.isEmpty,
               let json = try? JSONSerialization.jsonObject(with: Data(bytes[offset..<(offset + length)])) as? [String: Any],
               let app = json["app"] as? [String: Any], let v = app["version"] as? [String: Any] {
                version = v["name"] as? String ?? ""
            }
            offset += length
        }
        return BundledWatchApp(name: name, package: package, version: version, data: bytes,
                               fingerprint: developerKey(bytes).map { package + "_" + $0 })
    }

    private static func readString(_ bytes: [UInt8], _ offset: inout Int, allowEmpty: Bool = false) -> String? {
        guard offset + 4 <= bytes.count else { return nil }
        let length = bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
        offset += 4
        guard (allowEmpty ? length >= 0 : length > 0), offset + length <= bytes.count else { return nil }
        defer { offset += length }
        return String(decoding: bytes[offset..<(offset + length)], as: UTF8.self)
    }

    // Trailing 32-byte header: "hw signed app   " + "1000" + [signature block length BE32] …
    private static func signatureLength(_ bytes: [UInt8]) -> Int {
        guard bytes.count > 32, Array(bytes[(bytes.count - 32)..<(bytes.count - 16)]) == Array("hw signed app   ".utf8) else { return 0 }
        return bytes[(bytes.count - 12)..<(bytes.count - 8)].reduce(0) { $0 << 8 | Int($1) }
    }

    // Public key of the developer certificate inside the embedded profile (uncompressed EC point, base64)
    static func developerKey(_ bytes: [UInt8]) -> String? {
        let tail = Data(bytes.suffix(min(bytes.count, 64 * 1024)))
        guard let start = tail.range(of: Data("{\"version-name\"".utf8)) else { return nil }
        var depth = 0
        var end: Int?
        for i in start.lowerBound..<tail.endIndex {
            if tail[i] == UInt8(ascii: "{") { depth += 1 }
            if tail[i] == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { end = i + 1; break }
            }
        }
        guard let end, let profile = try? JSONSerialization.jsonObject(with: tail[start.lowerBound..<end]) as? [String: Any],
              let info = profile["bundle-info"] as? [String: Any] else { return nil }
        let pem = (info["development-certificate"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? info["distribution-certificate"] as? String ?? ""
        let body = pem.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: body), let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let key = SecCertificateCopyKey(certificate),
              let external = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return external.base64EncodedString()
    }
}

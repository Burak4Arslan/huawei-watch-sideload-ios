import UIKit

// The watch's notification icon service (Gadgetbridge HuaweiP2PAppIcon). Without it the watch shows its default icon
// for apps it doesn't know. Over P2P the phone offers the app (6001: package, name, version hash); if the watch has
// no icon for it, it answers 6001 with retCode 10001–10003 and the size it wants (152×152 on a GT 3 SE). The phone
// uploads the icon (file type 7, addressed to the service) and confirms with 6002. 10004/10005 = it already has one.
enum NotificationIcon {
    static let phoneModule = "hw.unitedevice.notificationpushapp"
    static let watchPackage = "in.huawei.NotificationAppIcon"
    static let phoneFingerprint = "UniteDeviceManagement"
    static let watchFingerprint = "SystemApp"
    static let fileType: UInt8 = 7

    static var appPackage: String { Bundle.main.bundleIdentifier ?? "huasideload" }

    // Java String.hashCode of package + version, as 8 hex digits (like Gadgetbridge's getAppHashInfo)
    static var appHash: String {
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        var hash: Int32 = 0
        for unit in (appPackage + version).utf16 { hash = hash &* 31 &+ Int32(unit) }
        return String(format: "%08x", UInt32(bitPattern: hash))
    }

    static func message(_ type: Int, _ body: [String: Any]) -> [UInt8] {
        Array((try? JSONSerialization.data(withJSONObject: ["msgType": type, "msgBody": body])) ?? Data())
    }

    static func offer() -> [UInt8] {
        message(6001, ["appInfoHash": appHash, "appPkgName": appPackage, "appName": AppInfo.displayName, "retCode": 10000])
    }

    // After the upload: 10001/2/3 → 10006/7/8
    static func uploaded(for retCode: Int) -> [UInt8] {
        message(6002, ["appPkgName": appPackage, "retCode": retCode + 5, "appInfoHash": appHash])
    }

    // "<hash>_<package without dots>_<1|2|3>.bin"
    static func fileName(for retCode: Int) -> String {
        "\(appHash)_\(appPackage.replacingOccurrences(of: ".", with: ""))_\(retCode - 10000).bin"
    }

    // The app's own icon, cut round like the watch's other icons, in the watch's image format:
    // little endian 0x2345, 0x8888, width, height, then ARGB pixels; 4+ equal pixels in a row as 0x23456789, pixel, count
    static func iconData(width: Int, height: Int) -> [UInt8]? {
        let name = ((Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconFiles"] as? [String]
        guard let icon = name?.last.flatMap(UIImage.init(named:)) ?? UIImage(named: "AppIcon"), let source = icon.cgImage else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        // Native byte order + premultipliedFirst: each UInt32 is 0xAARRGGBB
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.addEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.clip()
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var out: [UInt8] = []
        func put16(_ v: UInt16) { out += [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func put32(_ v: UInt32) { out += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
        put16(0x2345); put16(0x8888); put16(UInt16(width)); put16(UInt16(height))
        var run = 1
        for j in 0..<pixels.count {
            if j == pixels.count - 1 || pixels[j] != pixels[j + 1] {
                if run < 4 {
                    for _ in 0..<run { put32(pixels[j]) }
                } else {
                    put32(0x2345_6789); put32(pixels[j]); put32(UInt32(run))
                }
                run = 1
            } else {
                run += 1
            }
        }
        return out
    }
}

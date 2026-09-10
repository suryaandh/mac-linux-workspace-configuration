import AppKit
import Foundation

// Edits com.apple.ncprefs so macOS itself never shows banners (alert style = None).
// Original flags are backed up so styles can be restored later.
enum NotificationSilencer {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.UserNotifications/Library/Preferences/com.apple.ncprefs.plist")
    }

    private static let backupKey = "ncprefsOriginalFlags"
    private static let styleMask: UInt64 = 0b11
    private static let enabledBit: UInt64 = 0x4000_0000_0000_0000 >> 2 // bit 50: notifications allowed

    static func canAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: plistURL.path)
            && FileManager.default.isWritableFile(atPath: plistURL.path)
    }

    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    static func silenceAll() -> Result<Int, Error> {
        guard canAccess() else {
            return .failure(NSError(domain: "NotificationSilencer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot read ncprefs — grant Full Disk Access to DynamicNotch"]))
        }
        do {
            let data = try Data(contentsOf: plistURL)
            var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            guard var apps = plist["apps"] as? [[String: Any]] else {
                return .failure(NSError(domain: "NotificationSilencer", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected ncprefs format (no apps array)"]))
            }

            var backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: UInt64] ?? [:]
            var changed = 0

            for i in apps.indices {
                guard let idData = apps[i]["bundle-id"] as? Data,
                      let bundleID = String(data: idData, encoding: .utf8) ?? String(data: idData, encoding: .ascii),
                      let flagsNumber = apps[i]["flags"] as? NSNumber else { continue }
                var flags = flagsNumber.uint64Value

                // Only touch apps that currently show banners or alerts.
                guard flags & styleMask != 0 else { continue }

                if backup[bundleID] == nil { backup[bundleID] = flags }
                flags &= ~styleMask // style = None, keep notifications enabled
                apps[i]["flags"] = NSNumber(value: flags)
                changed += 1
            }

            guard changed > 0 else {
                UserDefaults.standard.set(backup, forKey: backupKey)
                return .success(0)
            }

            plist["apps"] = apps
            let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try out.write(to: plistURL, options: .atomic)

            UserDefaults.standard.set(backup, forKey: backupKey)
            restartNotificationCenter()
            return .success(changed)
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    static func restore() -> Result<Int, Error> {
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: UInt64], !backup.isEmpty else {
            return .success(0)
        }
        guard canAccess() else {
            return .failure(NSError(domain: "NotificationSilencer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot read ncprefs — grant Full Disk Access to DynamicNotch"]))
        }
        do {
            let data = try Data(contentsOf: plistURL)
            var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            guard var apps = plist["apps"] as? [[String: Any]] else { return .success(0) }

            var restored = 0
            for i in apps.indices {
                guard let idData = apps[i]["bundle-id"] as? Data,
                      let bundleID = String(data: idData, encoding: .utf8) ?? String(data: idData, encoding: .ascii),
                      let original = backup[bundleID] else { continue }
                apps[i]["flags"] = NSNumber(value: original)
                restored += 1
            }

            plist["apps"] = apps
            let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try out.write(to: plistURL, options: .atomic)

            UserDefaults.standard.removeObject(forKey: backupKey)
            restartNotificationCenter()
            return .success(restored)
        } catch {
            return .failure(error)
        }
    }

    static func hasBackup() -> Bool {
        let backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: UInt64]
        return !(backup?.isEmpty ?? true)
    }

    // Restart both daemon and UI so the new flags take effect immediately.
    private static func restartNotificationCenter() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["usernoted", "NotificationCenter"]
        try? task.run()
        task.waitUntilExit()
    }
}

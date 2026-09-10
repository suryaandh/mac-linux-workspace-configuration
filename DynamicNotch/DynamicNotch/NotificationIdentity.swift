import AppKit

struct NotificationIdentity: Decodable, Sendable {
    let name: String
    let bundleID: String
    let aliases: [String]
    let asset: String

    nonisolated static let catalog: [NotificationIdentity] = {
        guard let url = Bundle.main.url(forResource: "NotificationIconCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([NotificationIdentity].self, from: data)) ?? []
    }()

    nonisolated static func resolve(_ value: String, catalog: [NotificationIdentity] = Self.catalog) -> NotificationIdentity? {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Common mirrored-app labels, keeping source detection out of message bodies.
        for suffix in [" (iphone)", " — iphone", " from iphone", " dari iphone"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        let host = URLComponents(string: name.contains("://") ? name : "https://" + name)?.host
        return catalog.first { identity in
            let keys = ([identity.name, identity.bundleID] + identity.aliases).map { $0.lowercased() }
            if keys.contains(name) { return true }
            // iPhone mirroring can prefix the original bundle ID.
            if [".", ":", "/"].contains(where: { name.hasSuffix($0 + identity.bundleID.lowercased()) }) { return true }
            return keys.filter { $0.contains(".") && !$0.contains(" ") }.contains { key in
                host == key || host?.hasSuffix("." + key) == true
            }
        }
    }

    static func icon(for source: String) -> NSImage? {
        if ["dynamicnotch", "com.ducking.app.dynamicnotch"].contains(source.lowercased()) {
            return NSImage(named: "DynamicNotchLogo")
        }
        // Catalog lookup (covers WhatsApp, Telegram, Slack, Shopee, etc.)
        if let identity = resolve(source), let image = NSImage(named: identity.asset) { return image }
        // Running app icon
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased() == source.lowercased() || $0.localizedName?.lowercased() == source.lowercased()
        }) { return app.icon }
        // Installed-but-not-running app
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) { return NSWorkspace.shared.icon(forFile: url.path) }
        // iPhone Mirroring: use its app icon as fallback for all mirrored notifications
        let iPhoneMirroringBundles = ["com.apple.iphone-mirroring", "com.apple.iphonemirroring",
                                      "com.apple.continuity.iphone-mirroring"]
        if iPhoneMirroringBundles.contains(source.lowercased()) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iPhone-Mirroring") {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        // Last resort: match running apps by localized name
        let sourceLower = source.lowercased()
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == sourceLower
        }) { return app.icon }
        return nil
    }
}

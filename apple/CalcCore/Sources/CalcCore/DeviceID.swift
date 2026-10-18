import Foundation

public enum DeviceID {
    /// A stable per-install id, created on first use.
    public static func current(_ defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceID")
        return id
    }
}

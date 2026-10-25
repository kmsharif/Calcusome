#if os(macOS)
import AppKit
import os

/// Checks GitHub Releases for a newer version, shows its changelog, and installs the DMG in place.
@MainActor final class Updater {
    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let htmlUrl: URL
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    private static let latest = URL(string: "https://api.github.com/repos/kmsharif/Calcusome/releases/latest")!
    private let log = Logger(subsystem: "com.calcusome.app", category: "update")
    private let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var busy = false

    /// Checks at launch, then once a day. Debug builds only check from the menu.
    func start() {
        #if !DEBUG
        Task {
            while true {
                await check(manual: false)
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
        #endif
    }

    func check(manual: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.latest)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(Release.self, from: data)
            if release.version.compare(current, options: .numeric) == .orderedDescending {
                await offer(release)
            } else if manual {
                alert("You're up to date", "Calcusome \(current) is the latest version.")
            }
        } catch {
            log.error("Update check failed: \(error)")
            if manual { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    private func offer(_ release: Release) async {
        let alert = NSAlert()
        alert.messageText = "Calcusome \(release.version) is available"
        alert.informativeText = "You have \(current). What's new:"
        alert.accessoryView = changelog(release.body ?? "")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let app = Bundle.main.bundleURL
            try await Self.install(dmg.browserDownloadUrl, over: app)
            // Reopen once this process has quit.
            let relaunch = Process()
            relaunch.executableURL = URL(filePath: "/bin/sh")
            relaunch.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", app.path]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            log.error("Update install failed: \(error)")
            self.alert("Couldn't install the update", "Download it from the release page instead.\n\n\(error.localizedDescription)")
            NSWorkspace.shared.open(release.htmlUrl)
        }
    }

    /// Downloads the DMG, copies its app next to `app`, then swaps it in.
    /// ponytail: trusts HTTPS from this repo's releases; ad-hoc builds have no stable signature to check against.
    private nonisolated static func install(_ dmgURL: URL, over app: URL) async throws {
        let files = FileManager.default
        let (dmg, _) = try await URLSession.shared.download(from: dmgURL)
        defer { try? files.removeItem(at: dmg) }
        let mount = files.temporaryDirectory.appending(path: UUID().uuidString)
        try run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path)
        defer { try? run("/usr/bin/hdiutil", "detach", mount.path, "-force") }

        let staged = app.deletingLastPathComponent().appending(path: ".Calcusome-update.app")
        try? files.removeItem(at: staged)
        try run("/usr/bin/ditto", mount.appending(path: "Calcusome.app").path, staged.path)
        _ = try files.replaceItemAt(app, withItemAt: staged)
    }

    private nonisolated static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "\(tool) failed (\(process.terminationStatus))"])
        }
    }

    private func changelog(_ text: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 180)
        scroll.borderType = .bezelBorder
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.string = text
        view.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        view.textContainerInset = NSSize(width: 4, height: 4)
        return scroll
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
#endif

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import os

/// A system-wide shortcut, registered with Carbon so it needs no Accessibility permission.
@MainActor final class GlobalHotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// Defaults to ⌥⌘=.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_Equal),
         modifiers: UInt32 = UInt32(optionKey | cmdKey),
         action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkey>.fromOpaque(userData!).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let registered = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4341_4C43), id: 1),
                                             GetApplicationEventTarget(), 0, &hotKey)
        if installed != noErr || registered != noErr {  // e.g. another app already holds the shortcut
            Logger(subsystem: "com.calcusome.app", category: "hotkey")
                .error("Global hotkey not registered (handler \(installed), hotkey \(registered))")
        }
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
#endif

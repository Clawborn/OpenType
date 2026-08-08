import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class ContextBridge {
    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func capture() -> CapturedContext {
        let application = NSWorkspace.shared.frontmostApplication
        return CapturedContext(
            selectedText: selectedText(),
            applicationName: application?.localizedName ?? "Unknown app",
            bundleIdentifier: application?.bundleIdentifier
        )
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func insert(_ text: String, pressEnter: Bool) async throws {
        guard accessibilityGranted else {
            requestAccessibilityPermission()
            throw OpenTypeError.accessibilityRequired
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postKey(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 350_000_000)

        if pressEnter {
            postKey(keyCode: CGKeyCode(kVK_Return), flags: [])
        }

        snapshot.restore(to: pasteboard)
    }

    func undoLastChange() throws {
        guard accessibilityGranted else {
            requestAccessibilityPermission()
            throw OpenTypeError.accessibilityRequired
        }
        postKey(keyCode: CGKeyCode(kVK_ANSI_Z), flags: .maskCommand)
    }

    private func selectedText() -> String? {
        guard accessibilityGranted,
              let focusedElement = focusedElement() else { return nil }
        var selectedValue: CFTypeRef?
        let selectionError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard
            selectionError == .success,
            let selected = selectedValue as? String,
            !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return selected
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard error == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
            ),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
            )
        else { return }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}

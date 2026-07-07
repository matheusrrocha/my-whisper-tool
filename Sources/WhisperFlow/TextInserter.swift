import AppKit

/// Inserts text at the cursor of the frontmost app by putting it on the
/// pasteboard and synthesizing Cmd+V, then restoring the previous clipboard.
@MainActor
final class TextInserter {
    func insert(_ text: String) {
        guard AXIsProcessTrusted() else {
            Log.insert.error("cannot paste: Accessibility not granted")
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown app"
        Log.insert.notice("inserting \(text.count, privacy: .public) chars into \(frontmost, privacy: .public)")

        let pasteboard = NSPasteboard.general

        var savedItems: [NSPasteboardItem] = []
        if Settings.shared.restoreClipboard {
            for item in pasteboard.pasteboardItems ?? [] {
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                savedItems.append(copy)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard a moment to settle before the synthetic paste,
        // and give the target app time to handle it before restoring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.postCmdV()
        }
        if !savedItems.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
                Log.insert.notice("clipboard restored")
            }
        }
    }

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 9 = kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            Log.insert.error("could not create synthetic Cmd+V events")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        Log.insert.notice("Cmd+V posted")
    }
}

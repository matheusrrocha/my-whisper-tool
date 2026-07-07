import AppKit

/// Inserts text at the cursor of the frontmost app by putting it on the
/// pasteboard and synthesizing Cmd+V, then restoring the previous clipboard.
@MainActor
final class TextInserter {
    func insert(_ text: String) {
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
        postCmdV()

        if !savedItems.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
            }
        }
    }

    private func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 9 = kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

import AppKit

protocol PasteInjector: AnyObject {
    func paste(_ text: String) throws
}

enum PasteInjectorError: LocalizedError {
    case clipboardWriteFailed
    case pasteEventFailed
    case accessibilityPermissionMissing

    var errorDescription: String? {
        switch self {
        case .clipboardWriteFailed:
            return "Could not place the transcription on the clipboard."
        case .pasteEventFailed:
            return "Could not send Command-V to the focused app."
        case .accessibilityPermissionMissing:
            return "アクセシビリティ権限を許可してから、もう一度試してください。"
        }
    }
}

final class ClipboardPasteInjector: PasteInjector {
    private let pasteDelay: TimeInterval
    private let accessibilityPermissionCheck: () -> Bool

    init(pasteDelay: TimeInterval, accessibilityPermissionCheck: @escaping () -> Bool = { PermissionGuide.isAccessibilityTrusted }) {
        self.pasteDelay = pasteDelay
        self.accessibilityPermissionCheck = accessibilityPermissionCheck
    }

    func paste(_ text: String) throws {
        guard accessibilityPermissionCheck() else {
            throw PasteInjectorError.accessibilityPermissionMissing
        }

        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(previousItems, to: pasteboard)
            throw PasteInjectorError.clipboardWriteFailed
        }

        guard sendPasteShortcut() else {
            restore(previousItems, to: pasteboard)
            throw PasteInjectorError.pasteEventFailed
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            self.restore(previousItems, to: pasteboard)
        }
    }

    private func sendPasteShortcut() -> Bool {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

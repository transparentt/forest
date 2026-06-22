import AppKit
import Carbon

protocol HotkeyMonitor: AnyObject {
    var onRightOptionDown: (() -> Void)? { get set }
    var onRightOptionUp: (() -> Void)? { get set }

    func start() throws
    func stop()
}

enum HotkeyMonitorError: LocalizedError {
    case eventTapUnavailable
    case accessibilityPermissionMissing

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "アクセシビリティ権限を許可してから、ホットキーを再試行してください。"
        case .eventTapUnavailable:
            return "ショートカットキーを検出できません。アクセシビリティと入力監視の許可を確認してください。"
        }
    }
}

final class CGEventHotkeyMonitor: HotkeyMonitor {
    var onRightOptionDown: (() -> Void)?
    var onRightOptionUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var configuredHotkey = AppConfig.Hotkey.default
    private var isHotkeyDown = false

    func start() throws {
        guard eventTap == nil else { return }
        guard PermissionGuide.isAccessibilityTrusted else {
            throw HotkeyMonitorError.accessibilityPermissionMissing
        }
        configuredHotkey = AppConfig.load().hotkey

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<CGEventHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.reenableEventTap()
            } else {
                monitor.handle(event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            throw HotkeyMonitorError.eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isHotkeyDown = false
    }

    private func handle(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard Int(keyCode) == configuredHotkey.keyCode else { return }

        let flags = event.flags
        let hotkeyIsDown = flags.contains(Self.flagMask(for: configuredHotkey.keyCode))

        if hotkeyIsDown && !isHotkeyDown {
            isHotkeyDown = true
            onRightOptionDown?()
        } else if !hotkeyIsDown && isHotkeyDown {
            isHotkeyDown = false
            onRightOptionUp?()
        }
    }

    private static func flagMask(for keyCode: Int) -> CGEventFlags {
        switch keyCode {
        case kVK_Command, kVK_RightCommand:
            return .maskCommand
        case kVK_Control, kVK_RightControl:
            return .maskControl
        case kVK_Option, kVK_RightOption:
            return .maskAlternate
        case kVK_Shift, kVK_RightShift:
            return .maskShift
        default:
            return .maskAlternate
        }
    }

    private func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
}

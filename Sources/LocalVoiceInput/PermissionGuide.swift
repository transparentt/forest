import AppKit
import ApplicationServices
import AVFoundation

enum PermissionGuide {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var microphoneStatusText: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "マイク: 許可済み"
        case .notDetermined:
            return "マイク: 未設定"
        case .denied, .restricted:
            return "マイク: ブロックされています"
        @unknown default:
            return "マイク: 状態不明"
        }
    }

    static var accessibilityStatusText: String {
        isAccessibilityTrusted ? "アクセシビリティ: 許可済み" : "アクセシビリティ: 設定が必要です"
    }

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

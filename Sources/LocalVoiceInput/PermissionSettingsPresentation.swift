import Foundation

enum PermissionSettingsPresentation {
    static let inputMonitoringTitle = "入力監視"
    static let inputMonitoringHelpText = "システム設定 > プライバシーとセキュリティ > 入力監視 で Forest がオンになっているか確認してください。"
    static let restoreDelays: [TimeInterval] = [0.0, 0.25, 0.8]
    static let restoreLevelResetDelay: TimeInterval = 1.2
}

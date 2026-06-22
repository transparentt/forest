import AppKit

@MainActor
final class StatusController: NSObject {
    enum State {
        case idle
        case preparing
        case recording
        case transcribing
        case error(String)

        var title: String {
            switch self {
            case .idle:
                return "待機中"
            case .preparing:
                return "準備中"
            case .recording:
                return "録音中"
            case .transcribing:
                return "変換中"
            case .error:
                return "要確認"
            }
        }
    }

    var onQuit: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onOpenPermissionSetup: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onCreateDefaultConfig: (() -> Void)?
    var onRestartHotkeyMonitor: (() -> Void)?
    var onCopyLastTranscription: (() -> Void)?

    private let item: NSStatusItem
    private let menu = NSMenu()
    private let icon = StatusBarIcon()
    private let stateItem = NSMenuItem(title: "待機中", action: nil, keyEquivalent: "")
    private let copyItem = NSMenuItem(title: "最後の変換結果をコピー", action: #selector(copyLast), keyEquivalent: "")
    private let setupPermissionsItem = NSMenuItem(title: "設定を開く", action: #selector(openPermissionSetup), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")

    override init() {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureMenu()
    }

    private func configureMenu() {
        item.button?.image = icon.image()
        item.button?.imagePosition = .imageOnly
        item.button?.contentTintColor = .white

        stateItem.isEnabled = false
        copyItem.target = self
        setupPermissionsItem.target = self
        quitItem.target = self

        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(setupPermissionsItem)
        menu.addItem(copyItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
    }

    func setState(_ state: State) {
        item.button?.image = icon.image()
        item.button?.contentTintColor = .white
        switch state {
        case .idle:
            stateItem.title = "待機中: ショートカットキーを押している間だけ録音します"
        case .preparing:
            stateItem.title = "準備中: ローカルサーバーを起動しています"
        case .recording:
            stateItem.title = "録音中..."
        case .transcribing:
            stateItem.title = "ローカルで文字起こし中..."
        case .error(let message):
            stateItem.title = message
        }
    }

    @objc private func copyLast() {
        onCopyLastTranscription?()
    }

    @objc private func openPermissions() {
        onOpenPermissions?()
    }

    @objc private func openPermissionSetup() {
        onOpenPermissionSetup?()
    }

    @objc private func openConfig() {
        onOpenConfig?()
    }

    @objc private func createDefaultConfig() {
        onCreateDefaultConfig?()
    }

    @objc private func restartHotkeyMonitor() {
        onRestartHotkeyMonitor?()
    }

    @objc private func quit() {
        onQuit?()
    }
}

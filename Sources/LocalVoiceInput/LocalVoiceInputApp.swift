import AppKit

@main
final class LocalVoiceInputApp: NSObject, NSApplicationDelegate {
    private var statusController: StatusController!
    private var coordinator: DictationCoordinator!
    private var permissionOnboarding: PermissionOnboardingController!

    static func main() {
        let app = NSApplication.shared
        let delegate = LocalVoiceInputApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusController = StatusController()
        self.statusController = statusController
        let permissionOnboarding = PermissionOnboardingController()
        self.permissionOnboarding = permissionOnboarding

        let config = AppConfig.load()
        let services = AppServices(config: config, statusController: statusController)
        self.coordinator = DictationCoordinator(services: services)
        permissionOnboarding.onRetryHotkeyMonitor = { [weak coordinator] in
            coordinator?.restartHotkeyMonitor()
        }

        statusController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusController.onOpenPermissions = {
            PermissionGuide.openSystemSettings()
        }
        statusController.onOpenPermissionSetup = { [weak permissionOnboarding] in
            permissionOnboarding?.show()
        }
        statusController.onOpenConfig = {
            NSWorkspace.shared.open(AppConfig.configDirectoryURL)
        }
        statusController.onCreateDefaultConfig = { [weak statusController] in
            do {
                try AppConfig.createDefaultConfigIfMissing()
                NSWorkspace.shared.activateFileViewerSelecting([AppConfig.configURL])
                statusController?.setState(.idle)
            } catch {
                statusController?.setState(.error(error.localizedDescription))
            }
        }
        statusController.onCopyLastTranscription = { [weak coordinator] in
            coordinator?.copyLastTranscription()
        }
        statusController.onRestartHotkeyMonitor = { [weak coordinator] in
            coordinator?.restartHotkeyMonitor()
        }

        coordinator.start()
        permissionOnboarding.showIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissionOnboarding.showIfNeeded()
        coordinator.restartHotkeyMonitor()
    }
}

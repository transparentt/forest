import AppKit

@MainActor
final class PermissionOnboardingController: NSObject {
    private enum Section {
        case customization
        case dictionary
        case logs
        case permissions
    }

    private let window: NSWindow
    private let titleLabel = NSTextField(labelWithString: "")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let pageContainer = NSView()

    private let customizationButton = NSButton(title: "カスタマイズ", target: nil, action: #selector(showCustomization))
    private let dictionaryButton = NSButton(title: "辞書", target: nil, action: #selector(showDictionary))
    private let logsButton = NSButton(title: "ログ", target: nil, action: #selector(showLogs))
    private let permissionsButton = NSButton(title: "権限設定", target: nil, action: #selector(showPermissions))

    private let customizationPage = NSView()
    private let customizationToggle = NSSwitch(frame: .zero)
    private let customizationToggleLabel = NSTextField(labelWithString: "カスタマイズを使用")
    private let voiceInstructionToggle = NSButton(checkboxWithTitle: "音声で指示する", target: nil, action: nil)
    private let voiceInstructionModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customizationPresetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customizationPresetNameField = NSTextField(string: "")
    private let saveCustomizationPresetButton = NSButton(title: "プリセット保存", target: nil, action: #selector(saveCustomizationPreset))
    private let deleteCustomizationPresetButton = NSButton(title: "削除", target: nil, action: #selector(deleteCustomizationPreset))
    private let customizationTextView = NSTextView()
    private let customizationScrollView = NSScrollView()
    private let saveCustomizationButton = NSButton(title: "適用", target: nil, action: #selector(saveCustomization))

    private let dictionaryPage = NSView()
    private let dictionaryToggle = NSButton(checkboxWithTitle: "辞書を使用", target: nil, action: nil)
    private let addDictionaryRowButton = NSButton(title: "+", target: nil, action: #selector(addDictionaryRow))
    private let saveDictionaryButton = NSButton(title: "保存", target: nil, action: #selector(saveDictionary))
    private let dictionaryScrollView = NSScrollView()
    private let dictionaryRowsView = NSView()
    private var dictionaryRows: [DictionaryEntryRowView] = []

    private let logsPage = NSView()
    private let logsTextView = NSTextView()
    private let logsScrollView = NSScrollView()
    private let loggingToggle = NSButton(checkboxWithTitle: "ログを記録", target: nil, action: nil)
    private let refreshLogsButton = NSButton(title: "更新", target: nil, action: #selector(refreshLogs))

    private let permissionsPage = NSView()
    private let microphoneStatus = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let hotkeyStatus = NSTextField(labelWithString: "")
    private let changeHotkeyButton = NSButton(title: "変更", target: nil, action: #selector(beginHotkeyCapture))
    private let requestMicButton = NSButton(title: "マイクを許可", target: nil, action: #selector(requestMicrophone))
    private let openSettingsButton = NSButton(title: "システム設定を開く", target: nil, action: #selector(openSettings))

    private var refreshTimer: Timer?
    private var hotkeyCaptureMonitor: Any?
    private var lastAccessibilityTrusted = PermissionGuide.isAccessibilityTrusted
    private var selectedSection: Section = .customization
    private var userClosedWindow = false

    var onRetryHotkeyMonitor: (() -> Void)?

    override init() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        let sidebar = SidebarBackgroundView(frame: NSRect(x: 0, y: 0, width: 170, height: 520))

        let separator = SeparatorView(frame: NSRect(x: 169, y: 0, width: 1, height: 520))
        titleLabel.frame = NSRect(x: 202, y: 462, width: 470, height: 30)
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        hint.frame = NSRect(x: 202, y: 22, width: 470, height: 18)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor

        pageContainer.frame = NSRect(x: 200, y: 54, width: 490, height: 398)

        Self.configureSidebarButton(customizationButton, y: 438)
        Self.configureSidebarButton(dictionaryButton, y: 398)
        Self.configureSidebarButton(logsButton, y: 358)
        Self.configureSidebarButton(permissionsButton, y: 318)
        sidebar.addSubview(customizationButton)
        sidebar.addSubview(dictionaryButton)
        sidebar.addSubview(logsButton)
        sidebar.addSubview(permissionsButton)

        content.addSubview(sidebar)
        content.addSubview(separator)
        content.addSubview(titleLabel)
        content.addSubview(pageContainer)
        content.addSubview(hint)

        self.window = NSWindow(
            contentRect: content.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )

        super.init()

        window.title = "Forest 設定"
        window.contentView = content
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        customizationButton.target = self
        dictionaryButton.target = self
        logsButton.target = self
        permissionsButton.target = self

        configureCustomizationPage()
        configureDictionaryPage()
        configureLogsPage()
        configurePermissionsPage()

        pageContainer.addSubview(customizationPage)
        pageContainer.addSubview(dictionaryPage)
        pageContainer.addSubview(logsPage)
        pageContainer.addSubview(permissionsPage)

        loadSettings()
        select(.customization)
        refresh()
    }

    func showIfNeeded() {
        if shouldShow && !userClosedWindow {
            show(section: .permissions)
        }
    }

    func show() {
        show(section: selectedSection)
    }

    private func show(section: Section) {
        userClosedWindow = false
        loadSettings()
        select(section)
        refresh()
        startRefreshing()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreSettingsWindowAfterPermissionPrompt() {
        window.level = .floating

        PermissionSettingsPresentation.restoreDelays.forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.window.deminiaturize(nil)
                self.window.makeKeyAndOrderFront(nil)
                self.window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + PermissionSettingsPresentation.restoreLevelResetDelay) { [weak self] in
            self?.window.level = .normal
        }
    }

    private var shouldShow: Bool {
        !PermissionGuide.isAccessibilityTrusted || PermissionGuide.microphoneStatusText != "マイク: 許可済み"
    }

    private func configureCustomizationPage() {
        customizationPage.frame = pageContainer.bounds

        let body = Self.label(
            "書き起こし後の文章を、指定した内容で整えます。",
            frame: NSRect(x: 0, y: 328, width: 490, height: 40),
            color: .secondaryLabelColor,
            multiline: true
        )

        customizationToggleLabel.frame = NSRect(x: 0, y: 306, width: 126, height: 18)
        customizationToggleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        customizationToggle.controlSize = .small
        customizationToggle.frame = NSRect(x: 402, y: 303, width: 38, height: 20)
        customizationToggle.target = self
        customizationToggle.action = #selector(toggleCustomization)

        voiceInstructionToggle.frame = NSRect(x: 0, y: 276, width: 160, height: 24)
        voiceInstructionToggle.font = .systemFont(ofSize: 13, weight: .medium)
        voiceInstructionToggle.target = self
        voiceInstructionToggle.action = #selector(toggleVoiceInstruction)

        voiceInstructionModePopup.frame = NSRect(x: 250, y: 274, width: 190, height: 28)
        voiceInstructionModePopup.addItem(withTitle: AppConfig.Customization.VoiceInstructionMode.append.displayName)
        voiceInstructionModePopup.item(at: 0)?.representedObject = AppConfig.Customization.VoiceInstructionMode.append.rawValue
        voiceInstructionModePopup.addItem(withTitle: AppConfig.Customization.VoiceInstructionMode.replace.displayName)
        voiceInstructionModePopup.item(at: 1)?.representedObject = AppConfig.Customization.VoiceInstructionMode.replace.rawValue
        voiceInstructionModePopup.target = self
        voiceInstructionModePopup.action = #selector(changeVoiceInstructionMode)

        customizationPresetPopup.frame = NSRect(x: 0, y: 236, width: 238, height: 28)
        customizationPresetPopup.target = self
        customizationPresetPopup.action = #selector(selectCustomizationPreset)

        customizationPresetNameField.frame = NSRect(x: 250, y: 236, width: 240, height: 28)
        customizationPresetNameField.placeholderString = "プリセット名"
        customizationPresetNameField.font = .systemFont(ofSize: 13)

        let promptLabel = Self.label(
            "指示",
            frame: NSRect(x: 0, y: 208, width: 120, height: 18),
            size: 12,
            weight: .medium,
            color: .secondaryLabelColor
        )

        customizationTextView.font = .systemFont(ofSize: 13)
        customizationTextView.isRichText = false
        customizationTextView.isAutomaticQuoteSubstitutionEnabled = false
        customizationTextView.isAutomaticDashSubstitutionEnabled = false
        customizationTextView.string = ""
        customizationTextView.textContainerInset = NSSize(width: 8, height: 8)
        customizationTextView.minSize = NSSize(width: 0, height: 0)
        customizationTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        customizationTextView.isVerticallyResizable = true
        customizationTextView.isHorizontallyResizable = false
        customizationTextView.textContainer?.containerSize = NSSize(width: 490, height: CGFloat.greatestFiniteMagnitude)
        customizationTextView.textContainer?.widthTracksTextView = true
        customizationTextView.delegate = self

        customizationScrollView.frame = NSRect(x: 0, y: 94, width: 490, height: 108)
        customizationScrollView.borderType = .bezelBorder
        customizationScrollView.hasVerticalScroller = true
        customizationScrollView.documentView = customizationTextView

        saveCustomizationButton.frame = NSRect(x: 394, y: 52, width: 96, height: 30)
        saveCustomizationButton.bezelStyle = .rounded
        saveCustomizationButton.font = .systemFont(ofSize: 12, weight: .medium)
        saveCustomizationButton.target = self

        saveCustomizationPresetButton.frame = NSRect(x: 250, y: 52, width: 132, height: 30)
        saveCustomizationPresetButton.bezelStyle = .rounded
        saveCustomizationPresetButton.font = .systemFont(ofSize: 12, weight: .medium)
        saveCustomizationPresetButton.target = self

        deleteCustomizationPresetButton.frame = NSRect(x: 0, y: 52, width: 72, height: 30)
        deleteCustomizationPresetButton.bezelStyle = .rounded
        deleteCustomizationPresetButton.font = .systemFont(ofSize: 12, weight: .medium)
        deleteCustomizationPresetButton.target = self

        customizationPage.addSubview(body)
        customizationPage.addSubview(customizationToggle)
        customizationPage.addSubview(customizationToggleLabel)
        customizationPage.addSubview(voiceInstructionToggle)
        customizationPage.addSubview(voiceInstructionModePopup)
        customizationPage.addSubview(customizationPresetPopup)
        customizationPage.addSubview(customizationPresetNameField)
        customizationPage.addSubview(promptLabel)
        customizationPage.addSubview(customizationScrollView)
        customizationPage.addSubview(deleteCustomizationPresetButton)
        customizationPage.addSubview(saveCustomizationPresetButton)
        customizationPage.addSubview(saveCustomizationButton)
    }

    private func configureDictionaryPage() {
        dictionaryPage.frame = pageContainer.bounds

        let body = Self.label(
            "固有名詞や専門用語を、対象ワードと変換ワードのペアで登録します。",
            frame: NSRect(x: 0, y: 342, width: 490, height: 22),
            color: .secondaryLabelColor
        )

        dictionaryToggle.frame = NSRect(x: 0, y: 304, width: 160, height: 24)
        dictionaryToggle.font = .systemFont(ofSize: 13, weight: .medium)
        dictionaryToggle.target = self
        dictionaryToggle.action = #selector(toggleDictionary)

        addDictionaryRowButton.frame = NSRect(x: 0, y: 40, width: 32, height: 30)
        addDictionaryRowButton.bezelStyle = .rounded
        addDictionaryRowButton.font = .systemFont(ofSize: 16, weight: .medium)
        addDictionaryRowButton.target = self

        saveDictionaryButton.frame = NSRect(x: 394, y: 40, width: 96, height: 30)
        saveDictionaryButton.bezelStyle = .rounded
        saveDictionaryButton.font = .systemFont(ofSize: 12, weight: .medium)
        saveDictionaryButton.target = self

        let sourceHeader = Self.label("対象ワード", frame: NSRect(x: 0, y: 270, width: 190, height: 18), size: 12, weight: .medium, color: .secondaryLabelColor)
        let targetHeader = Self.label("変換ワード", frame: NSRect(x: 238, y: 270, width: 190, height: 18), size: 12, weight: .medium, color: .secondaryLabelColor)

        dictionaryScrollView.frame = NSRect(x: 0, y: 78, width: 490, height: 186)
        dictionaryScrollView.borderType = .noBorder
        dictionaryScrollView.drawsBackground = false
        dictionaryScrollView.hasVerticalScroller = true
        dictionaryScrollView.documentView = dictionaryRowsView

        dictionaryRowsView.frame = NSRect(x: 0, y: 0, width: 470, height: 186)

        dictionaryPage.addSubview(body)
        dictionaryPage.addSubview(dictionaryToggle)
        dictionaryPage.addSubview(addDictionaryRowButton)
        dictionaryPage.addSubview(sourceHeader)
        dictionaryPage.addSubview(targetHeader)
        dictionaryPage.addSubview(dictionaryScrollView)
        dictionaryPage.addSubview(saveDictionaryButton)
    }

    private func configurePermissionsPage() {
        permissionsPage.frame = pageContainer.bounds

        let body = Self.label(
            "設定したショートカットキーで録音するために必要な許可です。音声はこのMac内だけで処理されます。",
            frame: NSRect(x: 0, y: 328, width: 490, height: 40),
            color: .secondaryLabelColor,
            multiline: true
        )

        let rows = [
            Self.permissionRow(title: "マイク", statusLabel: microphoneStatus, y: 276),
            Self.permissionRow(title: "アクセシビリティ", statusLabel: accessibilityStatus, y: 232),
            Self.hotkeyRow(statusLabel: hotkeyStatus, button: changeHotkeyButton, y: 188)
        ]

        let inputMonitoringTitle = Self.label(
            PermissionSettingsPresentation.inputMonitoringTitle,
            frame: NSRect(x: 0, y: 138, width: 120, height: 18),
            size: 13,
            weight: .medium
        )
        let inputMonitoringHelp = Self.label(
            PermissionSettingsPresentation.inputMonitoringHelpText,
            frame: NSRect(x: 0, y: 104, width: 490, height: 32),
            size: 12,
            color: .secondaryLabelColor,
            multiline: true
        )

        requestMicButton.frame = NSRect(x: 0, y: 48, width: 112, height: 30)
        requestMicButton.bezelStyle = .rounded
        requestMicButton.font = .systemFont(ofSize: 12, weight: .medium)
        requestMicButton.target = self

        openSettingsButton.frame = NSRect(x: 124, y: 48, width: 148, height: 30)
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.font = .systemFont(ofSize: 12, weight: .medium)
        openSettingsButton.target = self

        changeHotkeyButton.target = self

        permissionsPage.addSubview(body)
        rows.forEach { permissionsPage.addSubview($0) }
        permissionsPage.addSubview(inputMonitoringTitle)
        permissionsPage.addSubview(inputMonitoringHelp)
        permissionsPage.addSubview(requestMicButton)
        permissionsPage.addSubview(openSettingsButton)
    }

    private func configureLogsPage() {
        logsPage.frame = pageContainer.bounds

        let body = Self.label(
            "直近の処理時間とGemma4に渡した内容を確認できます。",
            frame: NSRect(x: 0, y: 342, width: 490, height: 22),
            color: .secondaryLabelColor
        )

        loggingToggle.frame = NSRect(x: 0, y: 304, width: 160, height: 24)
        loggingToggle.font = .systemFont(ofSize: 13, weight: .medium)
        loggingToggle.target = self
        loggingToggle.action = #selector(toggleLogging)

        refreshLogsButton.frame = NSRect(x: 394, y: 300, width: 96, height: 30)
        refreshLogsButton.bezelStyle = .rounded
        refreshLogsButton.font = .systemFont(ofSize: 12, weight: .medium)
        refreshLogsButton.target = self

        logsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logsTextView.isEditable = false
        logsTextView.isRichText = false
        logsTextView.drawsBackground = false
        logsTextView.textContainerInset = NSSize(width: 0, height: 4)

        logsScrollView.frame = NSRect(x: 0, y: 0, width: 490, height: 286)
        logsScrollView.borderType = .noBorder
        logsScrollView.drawsBackground = false
        logsScrollView.hasVerticalScroller = true
        logsScrollView.documentView = logsTextView
        logsTextView.minSize = NSSize(width: 0, height: 0)
        logsTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logsTextView.isVerticallyResizable = true
        logsTextView.isHorizontallyResizable = false
        logsTextView.textContainer?.containerSize = NSSize(width: 490, height: CGFloat.greatestFiniteMagnitude)
        logsTextView.textContainer?.widthTracksTextView = true

        logsPage.addSubview(body)
        logsPage.addSubview(loggingToggle)
        logsPage.addSubview(refreshLogsButton)
        logsPage.addSubview(logsScrollView)
    }

    @objc private func showCustomization() {
        select(.customization)
    }

    @objc private func showDictionary() {
        select(.dictionary)
    }

    @objc private func showLogs() {
        select(.logs)
        refreshLogs()
    }

    @objc private func showPermissions() {
        select(.permissions)
        refresh()
    }

    private func select(_ section: Section) {
        selectedSection = section
        customizationPage.isHidden = section != .customization
        dictionaryPage.isHidden = section != .dictionary
        logsPage.isHidden = section != .logs
        permissionsPage.isHidden = section != .permissions

        updateSidebarButton(customizationButton, selected: section == .customization)
        updateSidebarButton(dictionaryButton, selected: section == .dictionary)
        updateSidebarButton(logsButton, selected: section == .logs)
        updateSidebarButton(permissionsButton, selected: section == .permissions)

        switch section {
        case .customization:
            titleLabel.stringValue = "カスタマイズ"
            hint.stringValue = "用途に合わせて文章の整え方を設定できます。"
        case .dictionary:
            titleLabel.stringValue = "辞書"
            hint.stringValue = "空の行は保存時に無視されます。"
        case .logs:
            titleLabel.stringValue = "ログ"
            hint.stringValue = "ASR、Gemma4、合計時間を記録しています。"
        case .permissions:
            titleLabel.stringValue = "権限設定"
            updatePermissionHint()
        }
    }

    @objc private func refreshLogs() {
        let entries = ProcessingLogStore.default.loadRecent(limit: 50).reversed()
        logsTextView.string = entries.map(Self.formatLogEntry).joined(separator: "\n\n")
        if logsTextView.string.isEmpty {
            logsTextView.string = "ログはまだありません。"
        }
    }

    private static func formatLogEntry(_ entry: ProcessingLogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [
            formatter.string(from: entry.timestamp),
            String(format: "ASR: %.2fs / Gemma4: %@ / 合計: %.2fs",
                   entry.asrDuration,
                   entry.gemmaDuration.map { String(format: "%.2fs", $0) } ?? "なし",
                   entry.totalDuration),
            "ASR出力: \(entry.asrText)"
        ]

        if let gemmaInput = entry.gemmaInput {
            if let modelCheck = entry.gemmaModelCheckDuration, let generation = entry.gemmaGenerationDuration {
                lines.append(String(format: "Gemma4内訳: モデル確認 %.2fs / 生成 %.2fs", modelCheck, generation))
            }
            lines.append("Gemma4入力: \(gemmaInput)")
        }
        lines.append("最終出力: \(entry.finalText)")
        return lines.joined(separator: "\n")
    }

    private func loadSettings() {
        let config = AppConfig.load()
        customizationToggle.state = config.customization.enabled ? .on : .off
        voiceInstructionToggle.state = config.customization.voiceInstructionEnabled ? .on : .off
        selectVoiceInstructionMode(config.customization.voiceInstructionMode)
        customizationTextView.string = config.customization.instruction
        customizationPresetNameField.stringValue = config.customization.presets.first { $0.id == config.customization.selectedPresetID }?.name ?? ""
        reloadCustomizationPresets(config.customization)
        dictionaryToggle.state = config.userDictionary.enabled ? .on : .off
        loggingToggle.state = config.logging.enabled ? .on : .off
        setDictionaryRows(config.userDictionary.entries)
        updateCustomizationControls()
        updateDictionaryControls()
    }

    @objc private func toggleLogging() {
        do {
            try AppConfig.saveLogging(.init(enabled: loggingToggle.state == .on))
            hint.stringValue = loggingToggle.state == .on ? "ログ記録をオンにしました。" : "ログ記録をオフにしました。"
        } catch {
            hint.stringValue = "ログ設定を保存できませんでした。"
        }
    }

    @objc private func toggleCustomization() {
        updateCustomizationControls()
        saveCustomization()
    }

    @objc private func toggleVoiceInstruction() {
        updateCustomizationControls()
        saveCustomization()
    }

    @objc private func changeVoiceInstructionMode() {
        updateCustomizationControls()
        saveCustomization()
    }

    @objc private func selectCustomizationPreset() {
        let customization = AppConfig.load().customization
        guard
            let id = customizationPresetPopup.selectedItem?.representedObject as? String,
            let preset = customization.presets.first(where: { $0.id == id })
        else {
            customizationPresetNameField.stringValue = ""
            persistCustomization(selectedPresetID: nil)
            return
        }

        customizationPresetNameField.stringValue = preset.name
        customizationTextView.string = preset.instruction
        persistCustomization(selectedPresetID: preset.id)
    }

    @objc private func toggleDictionary() {
        updateDictionaryControls()
        saveDictionary()
    }

    @objc private func saveCustomization() {
        persistCustomization(selectedPresetID: AppConfig.load().customization.selectedPresetID)
    }

    private func persistCustomization(selectedPresetID: String?) {
        let current = AppConfig.load()
        let customization = AppConfig.Customization(
            enabled: customizationToggle.state == .on,
            model: current.customization.model,
            serverURL: current.customization.serverURL,
            backendURL: current.customization.backendURL,
            timeout: current.customization.timeout,
            instruction: customizationTextView.string,
            selectedPresetID: selectedPresetID,
            presets: current.customization.presets,
            voiceInstructionEnabled: voiceInstructionToggle.state == .on,
            voiceInstructionMode: selectedVoiceInstructionMode()
        )

        do {
            try AppConfig.saveCustomization(customization)
            updateCustomizationControls()
            hint.stringValue = customization.isEnabled ? "カスタマイズを適用しました。" : "カスタマイズをオフにしました。"
        } catch {
            hint.stringValue = "カスタマイズを適用できませんでした。"
        }
    }

    @objc private func saveCustomizationPreset() {
        let current = AppConfig.load()
        let name = customizationPresetNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = customizationTextView.string
        guard !name.isEmpty, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hint.stringValue = "プリセット名と指示を入力してください。"
            return
        }

        let selectedID = current.customization.selectedPresetID
        var presets = current.customization.presets
        let presetID: String
        if let selectedID, let index = presets.firstIndex(where: { $0.id == selectedID }) {
            presetID = selectedID
            presets[index] = .init(id: selectedID, name: name, instruction: instruction)
        } else if let index = presets.firstIndex(where: { $0.name == name }) {
            presetID = presets[index].id
            presets[index] = .init(id: presetID, name: name, instruction: instruction)
        } else {
            let preset = AppConfig.Customization.Preset(name: name, instruction: instruction)
            presetID = preset.id
            presets.append(preset)
        }

        let customization = AppConfig.Customization(
            enabled: customizationToggle.state == .on,
            model: current.customization.model,
            serverURL: current.customization.serverURL,
            backendURL: current.customization.backendURL,
            timeout: current.customization.timeout,
            instruction: instruction,
            selectedPresetID: presetID,
            presets: presets,
            voiceInstructionEnabled: current.customization.voiceInstructionEnabled,
            voiceInstructionMode: current.customization.voiceInstructionMode
        )

        do {
            try AppConfig.saveCustomization(customization)
            reloadCustomizationPresets(customization)
            hint.stringValue = "プリセットを保存しました。"
        } catch {
            hint.stringValue = "プリセットを保存できませんでした。"
        }
    }

    @objc private func deleteCustomizationPreset() {
        let current = AppConfig.load()
        guard let selectedID = current.customization.selectedPresetID else {
            hint.stringValue = "削除するプリセットを選択してください。"
            return
        }

        let presets = current.customization.presets.filter { $0.id != selectedID }
        let customization = AppConfig.Customization(
            enabled: current.customization.enabled,
            model: current.customization.model,
            serverURL: current.customization.serverURL,
            backendURL: current.customization.backendURL,
            timeout: current.customization.timeout,
            instruction: current.customization.instruction,
            selectedPresetID: nil,
            presets: presets,
            voiceInstructionEnabled: current.customization.voiceInstructionEnabled,
            voiceInstructionMode: current.customization.voiceInstructionMode
        )

        do {
            try AppConfig.saveCustomization(customization)
            customizationPresetNameField.stringValue = ""
            reloadCustomizationPresets(customization)
            hint.stringValue = "プリセットを削除しました。"
        } catch {
            hint.stringValue = "プリセットを削除できませんでした。"
        }
    }

    @objc private func saveDictionary() {
        let userDictionary = AppConfig.UserDictionary(
            enabled: dictionaryToggle.state == .on,
            entries: dictionaryEntriesFromRows()
        )

        do {
            try AppConfig.saveUserDictionary(userDictionary)
            if userDictionary.enabled, userDictionary.entries.isEmpty {
                hint.stringValue = "辞書をオンにしました。対象ワードを追加してください。"
            } else {
                hint.stringValue = userDictionary.isEnabled ? "辞書を保存しました。" : "辞書をオフにしました。"
            }
        } catch {
            hint.stringValue = "辞書を保存できませんでした。"
        }
    }

    @objc private func addDictionaryRow() {
        appendDictionaryRow(source: "", target: "")
        layoutDictionaryRows()
        updateDictionaryControls()
    }

    private func setDictionaryRows(_ entries: [AppConfig.UserDictionary.Entry]) {
        dictionaryRows.forEach { $0.removeFromSuperview() }
        dictionaryRows.removeAll()

        if entries.isEmpty {
            appendDictionaryRow(source: "", target: "")
        } else {
            entries.forEach { appendDictionaryRow(source: $0.source, target: $0.target) }
        }
        layoutDictionaryRows()
    }

    private func appendDictionaryRow(source: String, target: String) {
        let row = DictionaryEntryRowView(source: source, target: target)
        dictionaryRows.append(row)
        dictionaryRowsView.addSubview(row)
    }

    private func layoutDictionaryRows() {
        let rowHeight: CGFloat = 38
        let contentHeight = max(186, CGFloat(dictionaryRows.count) * rowHeight + 8)
        dictionaryRowsView.frame = NSRect(x: 0, y: 0, width: 470, height: contentHeight)

        for (index, row) in dictionaryRows.enumerated() {
            let y = contentHeight - CGFloat(index + 1) * rowHeight
            row.frame = NSRect(x: 8, y: y, width: 448, height: 30)
            row.layoutFields()
        }
    }

    private func dictionaryEntriesFromRows() -> [AppConfig.UserDictionary.Entry] {
        dictionaryRows.compactMap { row in
            let source = row.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = row.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !target.isEmpty else { return nil }
            return AppConfig.UserDictionary.Entry(source: source, target: target)
        }
    }

    private func updateCustomizationControls() {
        let customizationEnabled = customizationToggle.state == .on
        let voiceInstructionEnabled = customizationEnabled && voiceInstructionToggle.state == .on
        customizationTextView.isEditable = customizationEnabled
        customizationTextView.textColor = customizationEnabled ? .textColor : .disabledControlTextColor
        voiceInstructionToggle.isEnabled = customizationEnabled
        voiceInstructionModePopup.isEnabled = voiceInstructionEnabled
        saveCustomizationButton.isEnabled = hasCustomizationChanges()
        saveCustomizationPresetButton.isEnabled = !customizationTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        deleteCustomizationPresetButton.isEnabled = AppConfig.load().customization.selectedPresetID != nil
    }

    private func hasCustomizationChanges() -> Bool {
        let customization = AppConfig.load().customization
        return customization.enabled != (customizationToggle.state == .on)
            || customization.instruction != customizationTextView.string
            || customization.selectedPresetID != (customizationPresetPopup.selectedItem?.representedObject as? String)
            || customization.voiceInstructionEnabled != (voiceInstructionToggle.state == .on)
            || customization.voiceInstructionMode != selectedVoiceInstructionMode()
    }

    private func selectedVoiceInstructionMode() -> AppConfig.Customization.VoiceInstructionMode {
        guard
            let rawValue = voiceInstructionModePopup.selectedItem?.representedObject as? String,
            let mode = AppConfig.Customization.VoiceInstructionMode(rawValue: rawValue)
        else {
            return .append
        }
        return mode
    }

    private func selectVoiceInstructionMode(_ mode: AppConfig.Customization.VoiceInstructionMode) {
        for index in 0..<voiceInstructionModePopup.numberOfItems {
            if voiceInstructionModePopup.item(at: index)?.representedObject as? String == mode.rawValue {
                voiceInstructionModePopup.selectItem(at: index)
                return
            }
        }
        voiceInstructionModePopup.selectItem(at: 0)
    }

    private func reloadCustomizationPresets(_ customization: AppConfig.Customization) {
        customizationPresetPopup.removeAllItems()
        customizationPresetPopup.addItem(withTitle: "プリセットなし")
        customizationPresetPopup.item(at: 0)?.representedObject = nil

        for preset in customization.presets {
            customizationPresetPopup.addItem(withTitle: preset.name)
            customizationPresetPopup.lastItem?.representedObject = preset.id
        }

        if let selectedID = customization.selectedPresetID,
           let index = customization.presets.firstIndex(where: { $0.id == selectedID }) {
            customizationPresetPopup.selectItem(at: index + 1)
        } else {
            customizationPresetPopup.selectItem(at: 0)
        }
        deleteCustomizationPresetButton.isEnabled = customization.selectedPresetID != nil
    }

    private func updateDictionaryControls() {
        let enabled = dictionaryToggle.state == .on
        addDictionaryRowButton.isEnabled = enabled
        saveDictionaryButton.isEnabled = enabled || !dictionaryEntriesFromRows().isEmpty
        dictionaryRows.forEach { $0.setEnabled(enabled) }
    }

    private func refresh() {
        let wasTrusted = lastAccessibilityTrusted
        let isTrusted = PermissionGuide.isAccessibilityTrusted
        lastAccessibilityTrusted = isTrusted

        updateStatus(microphoneStatus, rawText: PermissionGuide.microphoneStatusText)
        updateStatus(accessibilityStatus, rawText: PermissionGuide.accessibilityStatusText)
        if hotkeyCaptureMonitor == nil {
            hotkeyStatus.stringValue = AppConfig.load().hotkey.displayName
            hotkeyStatus.textColor = .labelColor
            changeHotkeyButton.isEnabled = true
            changeHotkeyButton.title = "変更"
        }

        if selectedSection == .permissions {
            updatePermissionHint()
        }

        if isTrusted && !wasTrusted {
            onRetryHotkeyMonitor?()
            if selectedSection == .permissions {
                restoreSettingsWindowAfterPermissionPrompt()
            }
        }
    }

    private func updatePermissionHint() {
        if PermissionGuide.microphoneStatusText == "マイク: 許可済み", PermissionGuide.isAccessibilityTrusted {
            hint.stringValue = "準備完了。設定したショートカットキーで録音できます。"
        } else {
            hint.stringValue = "許可後はこの画面を開いたままで自動更新されます。"
        }
    }

    private func updateStatus(_ label: NSTextField, rawText: String) {
        if rawText.contains("許可済み") {
            label.stringValue = "許可済み"
            label.textColor = .labelColor
        } else if rawText.contains("未設定") {
            label.stringValue = "未設定"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = "設定が必要"
            label.textColor = .labelColor
        }
    }

    private func startRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func requestMicrophone() {
        PermissionGuide.requestMicrophone { [weak self] _ in
            guard let self else { return }
            self.refresh()
            self.restoreSettingsWindowAfterPermissionPrompt()
        }
    }

    @objc private func openSettings() {
        PermissionGuide.openSystemSettings()
    }

    @objc private func beginHotkeyCapture() {
        hotkeyCaptureMonitor.map(NSEvent.removeMonitor)
        hotkeyStatus.stringValue = "押してください"
        hotkeyStatus.textColor = .secondaryLabelColor
        changeHotkeyButton.isEnabled = false

        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.captureHotkey(from: event)
            }
            return event
        }
    }

    private func captureHotkey(from event: NSEvent) {
        guard hotkeyCaptureMonitor != nil else { return }

        guard let hotkey = Self.hotkey(for: Int(event.keyCode)) else {
            hotkeyStatus.stringValue = "対応していません"
            hotkeyStatus.textColor = .secondaryLabelColor
            endHotkeyCapture()
            return
        }

        do {
            try AppConfig.saveHotkey(hotkey)
            hotkeyStatus.stringValue = hotkey.displayName
            hotkeyStatus.textColor = .labelColor
            endHotkeyCapture()
            onRetryHotkeyMonitor?()
        } catch {
            hotkeyStatus.stringValue = "保存できません"
            hotkeyStatus.textColor = .labelColor
            endHotkeyCapture()
        }
    }

    private func endHotkeyCapture() {
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
        }
        hotkeyCaptureMonitor = nil
        changeHotkeyButton.isEnabled = true
        changeHotkeyButton.title = "変更"
    }

    private static func configureSidebarButton(_ button: NSButton, y: CGFloat) {
        button.frame = NSRect(x: 14, y: y, width: 142, height: 32)
        button.bezelStyle = .inline
        button.setButtonType(.toggle)
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.isBordered = false
    }

    private func updateSidebarButton(_ button: NSButton, selected: Bool) {
        button.state = selected ? .on : .off
        let color: NSColor = selected ? .labelColor : .secondaryLabelColor
        let weight: NSFont.Weight = selected ? .semibold : .medium
        let title = NSAttributedString(
            string: button.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: weight),
                .foregroundColor: color
            ]
        )
        button.attributedTitle = title
        button.attributedAlternateTitle = title
        button.contentTintColor = color
    }

    private static func label(
        _ text: String,
        frame: NSRect,
        size: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        multiline: Bool = false
    ) -> NSTextField {
        let label = multiline ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private static func permissionRow(title: String, statusLabel: NSTextField, y: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: y, width: 490, height: 38))

        let titleLabel = label(title, frame: NSRect(x: 0, y: 10, width: 220, height: 18), size: 13, weight: .medium)
        statusLabel.frame = NSRect(x: 340, y: 10, width: 150, height: 18)
        statusLabel.alignment = .right
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let separator = SeparatorView(frame: NSRect(x: 0, y: 0, width: 490, height: 1))
        row.addSubview(titleLabel)
        row.addSubview(statusLabel)
        row.addSubview(separator)
        return row
    }

    private static func hotkeyRow(statusLabel: NSTextField, button: NSButton, y: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: y, width: 490, height: 38))

        let titleLabel = label("ショートカットキー", frame: NSRect(x: 0, y: 10, width: 180, height: 18), size: 13, weight: .medium)
        statusLabel.frame = NSRect(x: 220, y: 10, width: 140, height: 18)
        statusLabel.alignment = .right
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        button.frame = NSRect(x: 394, y: 5, width: 96, height: 28)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)

        let separator = SeparatorView(frame: NSRect(x: 0, y: 0, width: 490, height: 1))
        row.addSubview(titleLabel)
        row.addSubview(statusLabel)
        row.addSubview(button)
        row.addSubview(separator)
        return row
    }

    private static func hotkey(for keyCode: Int) -> AppConfig.Hotkey? {
        switch keyCode {
        case 61:
            return .init(keyCode: keyCode, displayName: "右Option")
        case 58:
            return .init(keyCode: keyCode, displayName: "左Option")
        case 54:
            return .init(keyCode: keyCode, displayName: "右Command")
        case 55:
            return .init(keyCode: keyCode, displayName: "左Command")
        case 62:
            return .init(keyCode: keyCode, displayName: "右Control")
        case 59:
            return .init(keyCode: keyCode, displayName: "左Control")
        default:
            return nil
        }
    }
}

private final class DictionaryEntryRowView: NSView {
    private let sourceField = NSTextField(string: "")
    private let targetField = NSTextField(string: "")
    private let arrowLabel = NSTextField(labelWithString: "→")

    var source: String { sourceField.stringValue }
    var target: String { targetField.stringValue }

    init(source: String, target: String) {
        super.init(frame: .zero)
        sourceField.stringValue = source
        targetField.stringValue = target
        sourceField.placeholderString = "例: くえん"
        targetField.placeholderString = "例: Qwen"
        sourceField.font = .systemFont(ofSize: 13)
        targetField.font = .systemFont(ofSize: 13)
        arrowLabel.alignment = .center
        arrowLabel.textColor = .secondaryLabelColor
        addSubview(sourceField)
        addSubview(arrowLabel)
        addSubview(targetField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutFields() {
        sourceField.frame = NSRect(x: 0, y: 2, width: 190, height: 26)
        arrowLabel.frame = NSRect(x: 198, y: 6, width: 32, height: 18)
        targetField.frame = NSRect(x: 238, y: 2, width: 190, height: 26)
    }

    func setEnabled(_ enabled: Bool) {
        sourceField.isEnabled = enabled
        targetField.isEnabled = enabled
    }
}

private final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

private final class SidebarBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
    }
}

extension PermissionOnboardingController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
        onRetryHotkeyMonitor?()
    }

    func windowWillClose(_ notification: Notification) {
        userClosedWindow = true
        endHotkeyCapture()
        stopRefreshing()
    }
}

extension PermissionOnboardingController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if notification.object as? NSTextView === customizationTextView {
            updateCustomizationControls()
        }
    }
}

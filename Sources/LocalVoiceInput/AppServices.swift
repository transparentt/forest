import Foundation

@MainActor
struct AppServices {
    let config: AppConfig
    let statusController: StatusController
    let hotkeyMonitor: HotkeyMonitor
    let audioRecorder: AudioRecorder
    let transcriptionEngine: TranscriptionEngine
    let textCustomizer: TextCustomizer
    let recordingHUD: RecordingHUDController
    let pasteInjector: PasteInjector
    let logStore: ProcessingLogStore

    init(config: AppConfig, statusController: StatusController) {
        self.config = config
        self.statusController = statusController
        self.hotkeyMonitor = CGEventHotkeyMonitor()
        self.audioRecorder = AVAudioFileRecorder(settings: config.recording)
        self.transcriptionEngine = ServerBackedTranscriptionEngine(config: config.transcription)
        self.textCustomizer = ServerBackedTextCustomizer()
        self.recordingHUD = RecordingHUDController()
        self.pasteInjector = ClipboardPasteInjector(pasteDelay: config.paste.restoreDelay)
        self.logStore = .default
    }
}

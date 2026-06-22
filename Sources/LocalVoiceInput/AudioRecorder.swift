import AVFoundation
import Foundation

struct AudioRecording {
    let url: URL
    let duration: TimeInterval
}

protocol AudioRecorder: AnyObject {
    func start() throws
    func stop() throws -> AudioRecording
    func currentLevel() -> Float
}

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case failedToCreateRecorder

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "Recording is not active."
        case .microphonePermissionDenied:
            return "Enable Microphone permission for Forest."
        case .failedToCreateRecorder:
            return "Could not start the audio recorder."
        }
    }
}

final class AVAudioFileRecorder: NSObject, AudioRecorder, AVAudioRecorderDelegate {
    private let settings: AppConfig.Recording
    private var recorder: AVAudioRecorder?
    private var startDate: Date?

    init(settings: AppConfig.Recording) {
        self.settings = settings
    }

    func start() throws {
        guard recorder == nil else {
            throw AudioRecorderError.alreadyRecording
        }

        try ensureMicrophonePermission()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("localvoiceinput-\(UUID().uuidString).wav")

        let recorderSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: settings.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: recorderSettings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw AudioRecorderError.failedToCreateRecorder
        }

        self.recorder = recorder
        self.startDate = Date()
    }

    func stop() throws -> AudioRecording {
        guard let recorder else {
            throw AudioRecorderError.notRecording
        }

        recorder.stop()
        self.recorder = nil

        let duration = startDate.map { Date().timeIntervalSince($0) } ?? 0
        startDate = nil

        return AudioRecording(url: recorder.url, duration: duration)
    }

    func currentLevel() -> Float {
        guard let recorder else {
            return 0
        }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        guard power.isFinite else {
            return 0
        }

        let floor: Float = -48
        let ceiling: Float = -12
        let normalized = (power - floor) / (ceiling - floor)
        return min(1, max(0, normalized))
    }

    private func ensureMicrophonePermission() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { value in
                granted = value
                semaphore.signal()
            }
            semaphore.wait()
            if granted {
                return
            }
            throw AudioRecorderError.microphonePermissionDenied
        case .denied, .restricted:
            throw AudioRecorderError.microphonePermissionDenied
        @unknown default:
            throw AudioRecorderError.microphonePermissionDenied
        }
    }
}

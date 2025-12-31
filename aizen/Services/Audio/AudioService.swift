import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
class AudioService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var partialTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionStatus: AudioPermissionManager.PermissionStatus = .notDetermined

    // Services
    private let permissionManager = AudioPermissionManager()
    private let speechRecognitionService = SpeechRecognitionService()
    private let audioRecordingService = AudioRecordingService()

    override init() {
        super.init()
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Permission status
        permissionManager.$permissionStatus
            .assign(to: &$permissionStatus)

        // Speech recognition
        speechRecognitionService.$transcribedText
            .assign(to: &$transcribedText)

        speechRecognitionService.$partialTranscription
            .assign(to: &$partialTranscription)

        // Audio recording
        audioRecordingService.$audioLevel
            .assign(to: &$audioLevel)

        audioRecordingService.$recordingDuration
            .assign(to: &$recordingDuration)
    }

    // MARK: - Permission Handling

    func requestPermissions() async -> Bool {
        return await permissionManager.requestPermissions()
    }

    func checkPermissions() async -> Bool {
        return await permissionManager.checkPermissions()
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        let hasPermissions = await checkPermissions()
        if !hasPermissions {
            let granted = await requestPermissions()
            guard granted else {
                throw RecordingError.permissionDenied
            }
        }

        // Reset state
        speechRecognitionService.resetTranscriptions()
        audioRecordingService.stopRecording()

        // Start services
        try await speechRecognitionService.startRecognition()
        audioRecordingService.startRecording()

        isRecording = true
    }

    func stopRecording() async -> String {
        isRecording = false

        // Stop services
        audioRecordingService.stopRecording()
        let finalText = await speechRecognitionService.stopRecognition()

        // Reset state
        speechRecognitionService.resetTranscriptions()

        return finalText
    }

    func cancelRecording() {
        isRecording = false

        audioRecordingService.cancelRecording()
        speechRecognitionService.cancelRecognition()
        speechRecognitionService.resetTranscriptions()
    }

    // MARK: - Errors

    enum RecordingError: LocalizedError {
        case permissionDenied
        case speechRecognitionUnavailable
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Speech Recognition permission is required. The microphone will be automatically requested when recording starts."
            case .speechRecognitionUnavailable:
                return "Speech recognition is not available. Please enable Siri in System Settings > Siri & Spotlight."
            case .recordingFailed:
                return "Failed to start recording. Please check microphone permissions in System Settings > Privacy & Security > Microphone."
            }
        }
    }
}

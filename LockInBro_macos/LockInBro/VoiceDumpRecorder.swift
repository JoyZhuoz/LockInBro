// VoiceDumpRecorder.swift — Voice recording + local Whisper transcription via WhisperKit
import Foundation
import AVFoundation
import WhisperKit

@Observable
@MainActor
final class VoiceDumpRecorder: NSObject {
    var isRecording = false
    var isTranscribing = false
    var liveTranscript = ""
    var permissionDenied = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var whisperKit: WhisperKit?

    // MARK: - Permissions

    func requestPermissions() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        permissionDenied = !granted
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording, !permissionDenied else { return }
        liveTranscript = ""

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedump_\(UUID().uuidString).wav")
        recordingURL = url

        // 16 kHz mono PCM — Whisper's native format, no conversion needed
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("VoiceDumpRecorder: failed to start — \(error)")
        }
    }

    func stopRecording() async {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else { return }
        recorder.stop()
        audioRecorder = nil
        isRecording = false

        isTranscribing = true
        do {
            liveTranscript = try await transcribe(url: url)
        } catch {
            print("VoiceDumpRecorder: transcription failed — \(error)")
        }
        isTranscribing = false

        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
    }

    // MARK: - Whisper Transcription

    /// Call this early (e.g. onAppear) so the model is ready before the user records.
    func warmUp() {
        guard whisperKit == nil else { return }
        Task {
            do { whisperKit = try await WhisperKit(model: "tiny") }
            catch { print("VoiceDumpRecorder: warm-up failed — \(error)") }
        }
    }

    private func transcribe(url: URL) async throws -> String {
        // Model should already be loaded from warmUp(); load now if not
        if whisperKit == nil {
            whisperKit = try await WhisperKit(model: "tiny")
        }
        guard let pipe = whisperKit else { return "" }
        let results = try await pipe.transcribe(audioPath: url.path)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

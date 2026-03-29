// SpeechService.swift — LockInBro
// On-device speech recognition via WhisperKit for Brain Dump voice input

import Foundation
import Combine
import AVFoundation
import WhisperKit
import Speech
import NaturalLanguage

@MainActor
final class SpeechService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = SpeechService()

    // WhisperKit Properties
    private var audioRecorder: AVAudioRecorder?
    private var whisperKit: WhisperKit?
    private let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent("braindump.wav")

    // Live Keyword Properties (For UI Bubbles)
    private let liveRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var liveRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var liveRecognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var transcript = ""
    @Published var latestKeyword: String? = nil
    @Published var isRecording = false
    @Published var isTranscribing = false
    // iOS 17+ API for microphone permissions
    @Published var authStatus = AVAudioApplication.shared.recordPermission
    @Published var modelLoadingState: String = "Not Loaded"

    private override init() {
        super.init()
        Task {
            await setupWhisper()
        }
    }

    // MARK: - Setup WhisperKit]

    private func setupWhisper() async {
        modelLoadingState = "Loading Local Model..."
        
        // 1. More robust way to find the folder path
        let folderName = "distil-whisper_distil-large-v3_594MB"
        guard let resourceURL = Bundle.main.resourceURL else {
            modelLoadingState = "Error: Resource bundle not found"
            return
        }
        
        let modelURL = resourceURL.appendingPathComponent(folderName)
        let fm = FileManager.default
        
        // 2. Check if the folder actually exists before trying to load it
        if !fm.fileExists(atPath: modelURL.path) {
            modelLoadingState = "Error: Folder not found in bundle"
            print("Looked for model at: \(modelURL.path)")
            return
        }

        do {
            // WhisperKit expects the directory path string
            whisperKit = try await WhisperKit(modelFolder: modelURL.path)
            modelLoadingState = "Ready"
        } catch {
            modelLoadingState = "Failed to load model: \(error.localizedDescription)"
            print("WhisperKit Init Error: \(error)")
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        // Modern iOS 17+ API for requesting mic permission
        let audioGranted = await AVAudioApplication.requestRecordPermission()
        
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        self.authStatus = (audioGranted && speechStatus == .authorized) ? .granted : .denied
    }

    // MARK: - Recording

    func startRecording() throws {
        self.transcript = ""
        self.latestKeyword = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true)

        // 1. Setup high-quality file recording for WhisperKit
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        audioRecorder = try AVAudioRecorder(url: tempAudioURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
        
        // 2. Setup lightweight live listener for UI Bubbles
        let inputNode = audioEngine.inputNode
        liveRecognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        liveRecognitionRequest?.shouldReportPartialResults = true
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        var seenWords = Set<String>()
        
        liveRecognitionTask = liveRecognizer?.recognitionTask(with: liveRecognitionRequest!) { [weak self] result, error in
            guard let self = self, let result = result else { return }
            
            let newText = result.bestTranscription.formattedString
            tagger.string = newText
            
            tagger.enumerateTags(in: newText.startIndex..<newText.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
                let word = String(newText[tokenRange]).capitalized
                
                // Only spawn bubbles for unique Nouns, Verbs, or Names
                if (tag == .noun || tag == .verb || tag == .organizationName) && !seenWords.contains(word) && word.count > 2 {
                    seenWords.insert(word)
                    DispatchQueue.main.async {
                        self.latestKeyword = word
                    }
                }
                return true
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.liveRecognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
    }

    func stopRecordingAndTranscribe() async throws -> String {
        // Stop file recorder
        audioRecorder?.stop()
        
        // Stop live listener
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            liveRecognitionRequest?.endAudio()
            liveRecognitionTask?.cancel()
        }
        
        isRecording = false
        isTranscribing = true
        
        guard let whisper = whisperKit else {
            isTranscribing = false
            throw NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded yet."])
        }

        do {
            let results = try await whisper.transcribe(audioPath: tempAudioURL.path)
            let finalTranscript = results.map { $0.text }.joined(separator: " ")
            
            self.transcript = finalTranscript
            self.isTranscribing = false
            return finalTranscript
            
        } catch {
            self.isTranscribing = false
            throw error
        }
    }

    func reset() {
        if isRecording {
            audioRecorder?.stop()
            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            isRecording = false
        }
        transcript = ""
        latestKeyword = nil
    }
}

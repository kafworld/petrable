import AVFoundation
import Combine
import SwiftUI
#if !os(macOS)
import UIKit
#endif

/// Records short voice prompts and transcribes them through the backend
/// (free Groq Whisper — the API key never leaves the server).
@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum RecState: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published var state: RecState = .idle
    private var recorder: AVAudioRecorder?
    private var activeTextHandler: ((String) -> Void)?
    private var observers: [NSObjectProtocol] = []

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("keithable-voice.m4a")
    }

    override init() {
        super.init()
        installAudioRecoveryObservers()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func toggle(onText: @escaping (String) -> Void) {
        switch state {
        case .idle:
            activeTextHandler = onText
            start()
        case .recording:
            activeTextHandler = onText
            finishRecording(shouldTranscribe: true)
        case .transcribing:
            break
        }
    }

    private func start() {
        Task {
            #if os(macOS)
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            #else
            let granted = await AVAudioApplication.requestRecordPermission()
            #endif
            guard granted else {
                Haptics.error()
                return
            }
            do {
                recorder?.stop()
                recorder = nil
                try? FileManager.default.removeItem(at: fileURL)
                #if !os(macOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
                try session.setActive(true)
                #endif
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 32_000,
                ]
                let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
                recorder.delegate = self
                recorder.prepareToRecord()
                guard recorder.record() else {
                    throw NSError(domain: "PetrableVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recorder did not start"])
                }
                self.recorder = recorder
                state = .recording
                Haptics.tap()
            } catch {
                print("Petrable voice: failed to start recording: \(error)")
                state = .idle
                Haptics.error()
            }
        }
    }

    private func finishRecording(shouldTranscribe: Bool) {
        let handler = activeTextHandler
        let wasRecording = recorder?.isRecording == true
        recorder?.delegate = nil
        if wasRecording {
            recorder?.stop()
        }
        recorder = nil
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        guard shouldTranscribe else {
            state = .idle
            return
        }
        state = .transcribing
        Haptics.tap()
        Task {
            defer { state = .idle }
            do {
                let data = try Data(contentsOf: fileURL)
                guard data.count > 2_000 else { return } // too short to bother
                let result: TranscriptionResult = try await ConvexService.shared.client.action(
                    "voice:transcribe",
                    with: ["audioBase64": data.base64EncodedString()]
                )
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    Haptics.success()
                    handler?(text)
                }
            } catch {
                print("Petrable voice: transcription failed: \(error)")
                Haptics.error()
            }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.state == .recording else { return }
            self.finishRecording(shouldTranscribe: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            print("Petrable voice: recorder encode error: \(String(describing: error))")
            self.finishRecording(shouldTranscribe: false)
            Haptics.error()
        }
    }

    private func installAudioRecoveryObservers() {
        #if !os(macOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            if type == .began {
                Task { @MainActor in
                    guard self.state == .recording else { return }
                    self.finishRecording(shouldTranscribe: true)
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .recording, self.recorder?.isRecording != true else { return }
                self.finishRecording(shouldTranscribe: true)
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .recording else { return }
                self.finishRecording(shouldTranscribe: true)
            }
        })
        #endif
    }
}

struct TranscriptionResult: Decodable {
    let text: String
}

/// Mic button that cycles idle → recording (red pulse) → transcribing.
struct VoiceButton: View {
    @ObservedObject var voice: VoiceRecorder
    /// "bare" renders just the glyph (home composer); "circle" matches the
    /// chat composer's circular buttons.
    var styleCircle = false
    let onText: (String) -> Void
    @State private var pulsing = false

    var body: some View {
        Button {
            voice.toggle(onText: onText)
        } label: {
            Group {
                switch voice.state {
                case .idle:
                    Image(systemName: "mic")
                        .font(.system(size: styleCircle ? 17 : 19, weight: .semibold))
                        .foregroundStyle(styleCircle ? .white.opacity(0.92) : .white)
                case .recording:
                    Image(systemName: "stop.fill")
                        .font(.system(size: styleCircle ? 15 : 17, weight: .bold))
                        .foregroundStyle(Theme.red)
                        .opacity(pulsing ? 0.45 : 1)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                                pulsing = true
                            }
                        }
                        .onDisappear { pulsing = false }
                case .transcribing:
                    ProgressView()
                        .tint(styleCircle ? .white : Theme.textSecondary)
                        .scaleEffect(0.8)
                }
            }
            .frame(width: styleCircle ? 44 : 28, height: styleCircle ? 44 : 28)
            .background(
                styleCircle ? AnyShapeStyle(Theme.surfaceLight.opacity(0.85)) : AnyShapeStyle(Color.clear),
                in: Circle()
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("voiceButton")
    }
}

/// The free model tiers the user can pick from, mirrored from convex/models.ts.
/// Routing (Gemini → Groq → OpenRouter) happens server-side in convex/freeAi.ts.
enum FreeModels {
    static let options: [(key: String, name: String, blurb: String)] = [
        ("free-smart", "Gemini Pro", "Most capable"),
        ("free-balanced", "Gemini Flash", "Balanced"),
        ("free-fast", "GPT-OSS 20B", "Fastest"),
        ("gpt-oss-120", "GPT-OSS 120B", "Smart · Groq"),
        ("deepseek-v3", "DeepSeek V3", "Smart · GitHub"),
        ("nemotron-3.5", "Nemotron 3.5", "Balanced · NVIDIA"),
        ("qwen-3.8", "Qwen 3.8", "Balanced · Cerebras"),
        ("llama-3.1-8b", "Llama 3.1 8B", "Fast · Cloudflare"),
    ]

    static func shortName(for key: String?) -> String {
        switch key {
        case "free-smart", "fable-5": return "Gemini Pro"
        case "free-balanced": return "Gemini Flash"
        case "free-fast": return "GPT-OSS 20B"
        case "gpt-oss-120": return "GPT-OSS 120B"
        case "deepseek-v3": return "DeepSeek V3"
        case "nemotron-3.5": return "Nemotron 3.5"
        case "qwen-3.8": return "Qwen 3.8"
        case "llama-3.1-8b": return "Llama 3.1 8B"
        default: return "Gemini Flash"
        }
    }
}

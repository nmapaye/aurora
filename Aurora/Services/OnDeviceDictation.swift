import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class OnDeviceDictation {
    var recording = false
    var transcript = ""
    var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = UUID()

    func start() async {
        guard !recording else { return }
        error = nil
        guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition else {
            error = "On-device dictation is unavailable for this language. You can type your request."; return
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard speech, microphone else { error = "Microphone or speech access is off. You can type instead."; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request; transcript = ""
            let id = UUID(); generation = id
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: engine.inputNode.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            hasTap = true; engine.prepare(); try engine.start(); recording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true || failure != nil
                Task { @MainActor in
                    guard let self, self.generation == id else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch { self.error = "Couldn't start local dictation. You can type instead."; stop() }
    }
    func stop() {
        generation = UUID(); engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

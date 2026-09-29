import Foundation

// `SpeechEngineID` + engine capabilities: Core/TTS/Engines/EngineDescriptor.swift.

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var engineID: SpeechEngineID { get }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }

    func prepareIfNeeded() async throws
    func speak(paragraphs: [String], startingAt index: Int, rate: Float, voiceID: String?) async throws
    func pause()
    func resume()
    func stop()
    func skip(by delta: Int)
    func setRate(_ rate: Float)
    func setVoice(id: String?)
    func renderParagraphToFile(text: String, destination: URL, rate: Float, voiceID: String?) async throws -> TimeInterval
}

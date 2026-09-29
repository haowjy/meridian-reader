import XCTest
@testable import Reader

/// CPU route (ONNX) input tensors: BOS/EOS padding with 0, voice-pack style row = len - 1
/// (clamped), speed, caps; plus the gain-matched WAV writer used for the A/B sample.
final class KokoroCPUInputsTests: XCTestCase {
    /// Pack where every float in row r equals Float(r), so the selected row is visible.
    private let pack: [Float] = (0..<510).flatMap { r in [Float](repeating: Float(r), count: 256) }

    func testIdsArePaddedWithZeroOnBothEnds() throws {
        let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: [50, 83, 156], phonemeCount: 3, voicePack: pack)
        XCTAssertEqual(inputs.inputIDs, [0, 50, 83, 156, 0])
        XCTAssertEqual(inputs.tokenCount, 3)
    }

    func testStyleRowIsPhonemeLengthMinusOne() throws {
        let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: Array(repeating: 1, count: 190), phonemeCount: 190, voicePack: pack)
        XCTAssertEqual(inputs.styleRow, 189)
        XCTAssertEqual(inputs.style.count, 256)
        XCTAssertTrue(inputs.style.allSatisfy { $0 == 189 })
    }

    func testStyleRowFollowsPhonemeStringNotIdCount() throws {
        // The vocab drops unknown symbols; FluidAudio still indexes by the phoneme-string length.
        let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: Array(repeating: 1, count: 498), phonemeCount: 501, voicePack: pack)
        XCTAssertEqual(inputs.styleRow, 500)
        XCTAssertEqual(inputs.inputIDs.count, 500)
    }

    func testStyleRowClamps() {
        XCTAssertEqual(KokoroCPUTensorBuilder.styleRow(phonemeCount: 0), 0)
        XCTAssertEqual(KokoroCPUTensorBuilder.styleRow(phonemeCount: 1), 0)
        XCTAssertEqual(KokoroCPUTensorBuilder.styleRow(phonemeCount: 510), 509)
        XCTAssertEqual(KokoroCPUTensorBuilder.styleRow(phonemeCount: 9999), 509)
    }

    func testSpeedDefaultsToOneAndIsPassedThrough() throws {
        XCTAssertEqual(try KokoroCPUTensorBuilder.build(tokenIDs: [1], phonemeCount: 1, voicePack: pack).speed, [1.0])
        XCTAssertEqual(try KokoroCPUTensorBuilder.build(tokenIDs: [1], phonemeCount: 1, voicePack: pack, speed: 1.25).speed, [1.25])
    }

    func testRejectsEmptyTooLongAndBadPack() {
        XCTAssertThrowsError(try KokoroCPUTensorBuilder.build(tokenIDs: [], phonemeCount: 0, voicePack: pack))
        XCTAssertThrowsError(try KokoroCPUTensorBuilder.build(tokenIDs: Array(repeating: 1, count: 511), phonemeCount: 511, voicePack: pack))
        XCTAssertThrowsError(try KokoroCPUTensorBuilder.build(tokenIDs: [1], phonemeCount: 1, voicePack: [0, 1, 2]))
    }

    func testShortCaseIsFirstThreeSentencesOf501PhonemePassage() {
        let long = KokoroCPUBenchText.longPhonemesMac
        XCTAssertEqual(long.count, 501)
        let short = KokoroCPUTensorBuilder.shortCase(fromLongPhonemes: long)
        XCTAssertEqual(short.count, 190)
        XCTAssertTrue(short.hasSuffix("əmˈɛɹəkə”."))
    }

    func testWavIsGainScaled16BitMono24k() {
        let wav = KokoroCPUAudio.wavData([0.5, -0.5, 2.0], gain: 0.69)
        XCTAssertEqual(wav.count, 44 + 6)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        let rate = wav.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: rate), 24_000)
        let s = wav.subdata(in: 44..<50).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(s[0], Int16((0.5 * 0.69 * 32767).rounded()))
        XCTAssertEqual(s[1], -s[0])
        XCTAssertEqual(s[2], 32767) // clipped
    }
}

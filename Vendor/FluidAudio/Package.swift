// swift-tools-version: 6.0
import PackageDescription
import Foundation

let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "FluidAudio",
            targets: ["FluidAudio"]
        ),
        .executable(
            name: "fluidaudiocli",
            targets: ["FluidAudioCLI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FluidAudio",
            dependencies: [
                "FastClusterWrapper",
                "MachTaskSelfWrapper",
                "NemoTextProcessing",
            ],
            path: "Sources/FluidAudio",
            exclude: ["ASR/Parakeet/Unified/benchmark.md"],
            resources: [
                // Keep .process: .copy of a Resources-named directory breaks Apple code signing on iOS.
                .process("TTS/LuxTts/G2p/Resources")
            ],
            // Reader patch: always optimize FluidAudio, even in the app's Debug configuration.
            // Unoptimized per-step sampling makes Nano decode ~3x slower (upstream Chatterbox.md).
            // Also keep vendored dependency warnings out of Reader's issue navigator; app warnings
            // stay enabled on Reader's own targets.
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                .unsafeFlags(["-suppress-warnings"]),
            ]
        ),
        // Byte-exact NeMo text normalization (FST engine, all 7 languages).
        // Prebuilt xcframework from FluidInference/text-processing-rs v0.3.1
        // (macOS, iOS, iOS Simulator and Mac Catalyst slices).
        // Always linked on tools < 6.2; Package@swift-6.2.swift exposes it as
        // the opt-out `NemoTextProcessing` trait (#880, #888).
        .binaryTarget(
            name: "NemoTextProcessing",
            url:
                "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.1/NemoTextProcessing.xcframework.zip",
            checksum: "5fa8c10d4ec26c1bb2413125f351a7222a4c68a23b74476680fbada7e26fc6aa"
        ),
        .target(
            name: "FastClusterWrapper",
            path: "Sources/FastClusterWrapper",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-w"])
            ]
        ),
        .target(
            name: "MachTaskSelfWrapper",
            path: "Sources/MachTaskSelfWrapper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "FluidAudioCLI",
            dependencies: ["FluidAudio"],
            path: "Sources/FluidAudioCLI",
            exclude: ["README.md"],
            resources: [
                .process("Utils/english.json")
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)

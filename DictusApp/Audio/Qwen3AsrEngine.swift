// DictusApp/Audio/Qwen3AsrEngine.swift
// FluidAudio Qwen3-ASR adapter, iOS 18+ only.
@preconcurrency import CoreML
import Foundation
import DictusCore
import FluidAudio

/// Qwen3-ASR 0.6B engine using FluidAudio's two-model Core ML pipeline.
///
/// Qwen is app-only and is never loaded by the keyboard extension. The manager
/// stays alive between transcriptions so Core ML models and embedding weights are
/// not reloaded for every dictation.
@available(iOS 18.0, *)
final class Qwen3AsrEngine: SpeechModelProtocol {
    var engineName: String { "Qwen3-ASR" }

    private var manager: Qwen3AsrManager?
    private var loadedModelName: String?

    var isReady: Bool {
        manager != nil
    }

    static func variant(for modelIdentifier: String) -> Qwen3AsrVariant? {
        switch modelIdentifier {
        case "qwen3-asr-0.6b-f32": return .f32
        case "qwen3-asr-0.6b-int8": return .int8
        default: return nil
        }
    }

    static func installedModelCacheDirectory(for modelIdentifier: String) -> URL? {
        guard let variant = variant(for: modelIdentifier) else { return nil }
        let directory = Qwen3AsrModels.defaultCacheDirectory(variant: variant)
        return Qwen3AsrModels.modelsExist(at: directory) ? directory : nil
    }

    func prepare(modelIdentifier: String) async throws {
        if loadedModelName == modelIdentifier, manager != nil {
            return
        }

        guard let directory = Self.installedModelCacheDirectory(for: modelIdentifier) else {
            throw SpeechModelError.modelNotInstalled(identifier: modelIdentifier)
        }

        do {
            let qwenManager = Qwen3AsrManager()
            try await qwenManager.loadModels(from: directory, computeUnits: .all)
            manager = qwenManager
            loadedModelName = modelIdentifier
            DictusLogger.app.info("Qwen3-ASR ready with model: \(modelIdentifier, privacy: .public)")
        } catch {
            manager = nil
            loadedModelName = nil
            DictusLogger.app.error("Qwen3-ASR initialization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        guard let manager else {
            throw TranscriptionError.notReady
        }
        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        do {
            let text = try await manager.transcribe(audioSamples: audioSamples, language: language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw TranscriptionError.transcriptionFailed("Empty Qwen3-ASR transcription result")
            }
            return text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.transcriptionFailed("Qwen3-ASR: \(error.localizedDescription)")
        }
    }
}

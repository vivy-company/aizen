import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Main Parakeet Model

@preconcurrency nonisolated public class ParakeetTDT: Module, @unchecked Sendable {
    public let preprocessConfig: PreprocessConfig
    public let encoderConfig: ConformerConfig
    public let vocabulary: [String]
    public let durations: [Int]
    public let maxSymbols: Int

    let encoder: Conformer
    let decoder: PredictNetwork
    let joint: JointNetwork

    public init(config: ParakeetTDTConfig) throws {
        guard config.decoding.modelType == "tdt" else {
            throw ParakeetError.invalidModelType("Model must be a TDT model")
        }

        self.preprocessConfig = config.preprocessor
        self.encoderConfig = config.encoder
        self.vocabulary = config.joint.vocabulary
        self.durations = config.decoding.durations
        // Set a default maxSymbols value if not provided in config to prevent infinite loops
        self.maxSymbols = config.decoding.greedy?["max_symbols"] as? Int ?? 10

        self.encoder = Conformer(config: config.encoder)
        self.decoder = PredictNetwork(config: config.decoder)
        self.joint = JointNetwork(config: config.joint)

        super.init()
    }

    /// Main transcription interface
    public func transcribe(
        audioData: MLXArray,
        dtype: DType = .float32,
        chunkDuration: Float? = nil,
        overlapDuration: Float = 15.0,
        chunkCallback: ((Float, Float) -> Void)? = nil
    ) throws -> AlignedResult {

        let processedAudio = audioData.dtype == dtype ? audioData : audioData.asType(dtype)

        // If no chunking requested or audio is short enough
        if let chunkDuration = chunkDuration {
            let audioLengthSeconds = Float(audioData.shape[0]) / Float(preprocessConfig.sampleRate)

            if audioLengthSeconds <= chunkDuration {
                let mel = try getLogMel(processedAudio, config: preprocessConfig)
                return try generate(mel: mel)[0]
            }

            // Process in chunks
            return try transcribeChunked(
                audio: processedAudio,
                chunkDuration: chunkDuration,
                overlapDuration: overlapDuration,
                chunkCallback: chunkCallback
            )
        } else {
            let mel = try getLogMel(processedAudio, config: preprocessConfig)
            return try generate(mel: mel)[0]
        }
    }

    private func transcribeChunked(
        audio: MLXArray,
        chunkDuration: Float,
        overlapDuration: Float,
        chunkCallback: ((Float, Float) -> Void)?
    ) throws -> AlignedResult {

        let chunkSamples = Int(chunkDuration * Float(preprocessConfig.sampleRate))
        let overlapSamples = Int(overlapDuration * Float(preprocessConfig.sampleRate))
        let audioLength = audio.shape[0]

        var allTokens: [AlignedToken] = []
        var start = 0

        while start < audioLength {
            let end = min(start + chunkSamples, audioLength)

            chunkCallback?(Float(end), Float(audioLength))

            if end - start < preprocessConfig.hopLength {
                break  // Prevent zero-length log mel
            }

            let chunkAudio = audio[start..<end]
            let chunkMel = try getLogMel(chunkAudio, config: preprocessConfig)
            let chunkResult = try generate(mel: chunkMel)[0]

            let chunkOffset = Float(start) / Float(preprocessConfig.sampleRate)
            var chunkTokens: [AlignedToken] = []

            for sentence in chunkResult.sentences {
                for var token in sentence.tokens {
                    token.start += chunkOffset
                    chunkTokens.append(token)
                }
            }

            if !allTokens.isEmpty {
                // Merge with overlap handling
                allTokens = try mergeLongestContiguous(
                    allTokens,
                    chunkTokens,
                    overlapDuration: overlapDuration
                )
            } else {
                allTokens = chunkTokens
            }

            start += chunkSamples - overlapSamples
        }

        return sentencesToResult(tokensToSentences(allTokens))
    }

    /// Public access to encoder for streaming
    public func encode(_ input: MLXArray, cache: [ConformerCache?]? = nil) -> (MLXArray, MLXArray) {
        return encoder(input, cache: cache)
    }

}

// MARK: - Error Types

nonisolated public enum ParakeetError: Error, LocalizedError {
    case invalidModelType(String)
    case unsupportedDecoding(String)
    case audioProcessingError(String)
    case modelLoadingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidModelType(let message):
            return "Invalid model type: \(message)"
        case .unsupportedDecoding(let message):
            return "Unsupported decoding: \(message)"
        case .audioProcessingError(let message):
            return "Audio processing error: \(message)"
        case .modelLoadingError(let message):
            return "Model loading error: \(message)"
        }
    }
}

#endif

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

    private let encoder: Conformer
    private let decoder: PredictNetwork
    private let joint: JointNetwork

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

    public func generate(mel: MLXArray) throws -> [AlignedResult] {
        let inputMel = mel.ndim == 2 ? mel.expandedDimensions(axis: 0) : mel

        let (features, lengths) = encoder(inputMel)

        let (results, _) = try decode(
            features: features,
            lengths: lengths,
            config: DecodingConfig()
        )

        return results.map { tokens in
            sentencesToResult(tokensToSentences(tokens))
        }
    }

    public func decode(
        features: MLXArray,
        lengths: MLXArray? = nil,
        lastToken: [Int?]? = nil,
        hiddenState: [(MLXArray, MLXArray)?]? = nil,
        config: DecodingConfig = DecodingConfig()
    ) throws -> ([[AlignedToken]], [(MLXArray, MLXArray)?]) {

        guard config.decoding == "greedy" else {
            throw ParakeetError.unsupportedDecoding(
                "Only greedy decoding is supported for TDT decoder")
        }

        let (B, S) = (features.shape[0], features.shape[1])
        let actualLengths = lengths ?? MLXArray(Array(repeating: S, count: B))
        let actualLastToken = lastToken ?? Array(repeating: nil, count: B)
        var actualHiddenState = hiddenState ?? Array(repeating: nil, count: B)

        var results: [[AlignedToken]] = []

        for batch in 0..<B {
            var hypothesis: [AlignedToken] = []
            let feature = features[batch].expandedDimensions(axis: 0)
            let length = Int(actualLengths[batch].item(Int32.self))

            var step = 0
            var newSymbols = 0
            var currentLastToken = actualLastToken[batch]

            while step < length {
                // Decoder pass
                let decoderInput = currentLastToken.map { token in
                    MLXArray([token]).expandedDimensions(axis: 0)  // Shape: [1, 1] (batch_size, seq_len)
                }

                let (decoderOut, newHidden) = decoder(decoderInput, actualHiddenState[batch])

                let decoderOutput = decoderOut.asType(feature.dtype)
                let decoderHidden = (
                    newHidden.0.asType(feature.dtype), newHidden.1.asType(feature.dtype)
                )

                // Joint pass
                let jointOut = joint(
                    feature[0..., step..<(step + 1)],
                    decoderOutput
                )

                // Ensure we're in inference mode
                MLX.eval(jointOut)

                // Check for NaN by comparing with itself (NaN != NaN is true)
                let jointOutNaNCheck = jointOut.max().item(Float.self)
                if jointOutNaNCheck.isNaN {
                    break
                }

                // Sampling - match Python implementation exactly
                let vocabSize = vocabulary.count

                // Check if we have enough dimensions and size
                guard jointOut.shape.count >= 4 else {
                    throw ParakeetError.audioProcessingError(
                        "Joint output has insufficient dimensions: \(jointOut.shape)")
                }

                let lastDim = jointOut.shape[jointOut.shape.count - 1]  // Always get the last dimension

                guard lastDim > vocabSize else {
                    throw ParakeetError.audioProcessingError(
                        "Joint output last dimension (\(lastDim)) is not larger than vocab size (\(vocabSize))"
                    )
                }

                // Match Python exactly: joint_out[0, 0, :, : len(self.vocabulary) + 1]
                // and joint_out[0, 0, :, len(self.vocabulary) + 1 :]
                let vocabSlice = jointOut[0, 0, 0..., 0..<(vocabSize + 1)]
                let decisionSlice = jointOut[0, 0, 0..., (vocabSize + 1)..<lastDim]

                guard vocabSlice.shape[0] > 0 && decisionSlice.shape[0] > 0 else {
                    throw ParakeetError.audioProcessingError(
                        "Empty slices: vocab=\(vocabSlice.shape), decision=\(decisionSlice.shape)")
                }

                // The joint output should be [batch, enc_time, pred_time, num_classes]
                // We want to argmax over the last dimension after slicing
                let predToken = Int(vocabSlice.argMax(axis: -1).item(Int32.self))
                let decision = Int(decisionSlice.argMax(axis: -1).item(Int32.self))

                // TDT decoding rule
                if predToken != vocabSize {
                    let tokenText = ParakeetTokenizer.decode([predToken], vocabulary)
                    let startTime =
                        Float(step * encoderConfig.subsamplingFactor)
                        / Float(preprocessConfig.sampleRate) * Float(preprocessConfig.hopLength)
                    let duration =
                        Float(durations[decision] * encoderConfig.subsamplingFactor)
                        / Float(preprocessConfig.sampleRate) * Float(preprocessConfig.hopLength)

                    hypothesis.append(
                        AlignedToken(
                            id: predToken,
                            start: startTime,
                            duration: duration,
                            text: tokenText
                        ))

                    currentLastToken = predToken
                    actualHiddenState[batch] = decoderHidden
                } else {
                }

                step += durations[decision]

                // Prevent stucking rule
                newSymbols += 1

                if durations[decision] != 0 {
                    newSymbols = 0
                } else {
                    if newSymbols >= maxSymbols {
                        step += 1
                        newSymbols = 0
                    }
                }

                // Safety break to prevent infinite loops
                if newSymbols > 100 {
                    break
                }

            }

            results.append(hypothesis)
        }

        return (results, actualHiddenState)
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

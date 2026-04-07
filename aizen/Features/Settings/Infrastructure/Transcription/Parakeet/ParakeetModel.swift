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

    /// Load weights from one or more safetensors files.
    public func loadWeights(from urls: [URL]) throws {
        var mappedWeights: [String: MLXArray] = [:]

        for url in urls {
            let weights = try MLX.loadArrays(url: url)
            for (safetensorsKey, weight) in weights {
                if let swiftKey = mapSafetensorsKeyToSwiftPath(safetensorsKey) {
                    mappedWeights[swiftKey] = weight
                }
            }
        }

        let flatWeights = ModuleParameters.unflattened(mappedWeights)
        self.update(parameters: flatWeights)
    }

    public func loadWeights(from url: URL) throws {
        try loadWeights(from: [url])
    }

    /// Maps safetensors parameter keys to Swift model parameter paths
    private func mapSafetensorsKeyToSwiftPath(_ safetensorsKey: String) -> String? {
        // Handle encoder parameters
        if safetensorsKey.hasPrefix("encoder.") {
            let encoderKey = String(safetensorsKey.dropFirst("encoder.".count))

            // Handle pre_encode parameters
            if encoderKey.hasPrefix("pre_encode.") {
                let preEncodeKey = String(encoderKey.dropFirst("pre_encode.".count))

                // Handle conv layers: "conv.0.weight" -> "conv.0.weight"
                if preEncodeKey.hasPrefix("conv.") {
                    // The conv layers are already in the right format for Swift
                    return "encoder.preEncode.\(preEncodeKey)"
                }

                // Handle out layer: "out.weight" -> "out.weight"
                if preEncodeKey.hasPrefix("out.") {
                    return "encoder.preEncode.\(preEncodeKey)"
                }
            }

            // Handle conformer layers: "layers.0.norm_self_att.weight" -> "layers.0.normSelfAtt.weight"
            if encoderKey.hasPrefix("layers.") {
                var layerKey = encoderKey

                // Convert snake_case to camelCase for Swift property names
                layerKey = layerKey.replacingOccurrences(of: "norm_self_att", with: "normSelfAtt")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.linear_q", with: "selfAttn.wq")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.linear_k", with: "selfAttn.wk")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.linear_v", with: "selfAttn.wv")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.linear_out", with: "selfAttn.wo")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.linear_pos", with: "selfAttn.linearPos")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.pos_bias_u", with: "selfAttn.posBiasU")
                layerKey = layerKey.replacingOccurrences(
                    of: "self_attn.pos_bias_v", with: "selfAttn.posBiasV")
                layerKey = layerKey.replacingOccurrences(of: "norm_conv", with: "normConv")
                layerKey = layerKey.replacingOccurrences(
                    of: "conv.pointwise_conv1", with: "conv.pointwiseConv1")
                layerKey = layerKey.replacingOccurrences(
                    of: "conv.depthwise_conv", with: "conv.depthwiseConv")
                layerKey = layerKey.replacingOccurrences(
                    of: "conv.batch_norm", with: "conv.batchNorm")
                layerKey = layerKey.replacingOccurrences(
                    of: "conv.pointwise_conv2", with: "conv.pointwiseConv2")
                layerKey = layerKey.replacingOccurrences(
                    of: "norm_feed_forward1", with: "normFeedForward1")
                layerKey = layerKey.replacingOccurrences(of: "feed_forward1", with: "feedForward1")
                layerKey = layerKey.replacingOccurrences(
                    of: "norm_feed_forward2", with: "normFeedForward2")
                layerKey = layerKey.replacingOccurrences(of: "feed_forward2", with: "feedForward2")
                layerKey = layerKey.replacingOccurrences(of: "norm_out", with: "normOut")

                return "encoder.\(layerKey)"
            }
        }

        // Handle decoder parameters
        if safetensorsKey.hasPrefix("decoder.") {
            var decoderKey = String(safetensorsKey.dropFirst("decoder.".count))

            // Convert snake_case to camelCase
            decoderKey = decoderKey.replacingOccurrences(of: "prediction.embed", with: "embed")
            decoderKey = decoderKey.replacingOccurrences(
                of: "prediction.dec_rnn.lstm", with: "decRNN.lstmLayers")

            return "decoder.\(decoderKey)"
        }

        // Handle joint parameters
        if safetensorsKey.hasPrefix("joint.") {
            var jointKey = String(safetensorsKey.dropFirst("joint.".count))

            // Convert snake_case to camelCase
            jointKey = jointKey.replacingOccurrences(of: "enc_proj", with: "encLinear")
            jointKey = jointKey.replacingOccurrences(of: "pred_proj", with: "predLinear")
            jointKey = jointKey.replacingOccurrences(of: "joint_proj", with: "jointLinear")

            // Handle direct enc/pred mappings
            jointKey = jointKey.replacingOccurrences(of: "enc.", with: "encLinear.")
            jointKey = jointKey.replacingOccurrences(of: "pred.", with: "predLinear.")

            // Handle joint_net layers - map to jointLinear since that's the final linear layer
            if jointKey.hasPrefix("joint_net.") {
                let jointNetKey = String(jointKey.dropFirst("joint_net.".count))
                // joint_net.2 is the final linear layer in Python, map to jointLinear
                if jointNetKey.hasPrefix("2.") {
                    let layerParam = String(jointNetKey.dropFirst("2.".count))
                    jointKey = "jointLinear.\(layerParam)"
                } else {
                    // Other joint_net layers (0 is activation, 1 is identity) - skip for now
                    return nil
                }
            }

            return "joint.\(jointKey)"
        }

        return nil
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

// MARK: - Utility Functions

nonisolated private func tokensToSentences(_ tokens: [AlignedToken]) -> [AlignedSentence] {
    guard !tokens.isEmpty else { return [] }

    var sentences: [AlignedSentence] = []
    var currentTokens: [AlignedToken] = []

    for token in tokens {
        currentTokens.append(token)

        // Simple sentence boundary detection (you might want to improve this)
        if token.text.contains(".") || token.text.contains("!") || token.text.contains("?") {
            sentences.append(AlignedSentence(tokens: currentTokens))
            currentTokens = []
        }
    }

    // Add remaining tokens as final sentence
    if !currentTokens.isEmpty {
        sentences.append(AlignedSentence(tokens: currentTokens))
    }

    return sentences
}

nonisolated private func sentencesToResult(_ sentences: [AlignedSentence]) -> AlignedResult {
    return AlignedResult(sentences: sentences)
}

nonisolated private func mergeLongestContiguous(
    _ tokens1: [AlignedToken],
    _ tokens2: [AlignedToken],
    overlapDuration: Float
) throws -> [AlignedToken] {
    // Simplified merge - you might want to implement a more sophisticated algorithm
    let cutoffTime = tokens1.last?.end ?? 0.0 - overlapDuration
    let filteredTokens1 = tokens1.filter { $0.end <= cutoffTime }
    let filteredTokens2 = tokens2.filter { $0.start >= cutoffTime }

    return filteredTokens1 + filteredTokens2
}

// MARK: - Streaming Support

nonisolated public class StreamingParakeet {
    let model: ParakeetTDT
    let contextSize: (Int, Int)
    let depth: Int
    let decodingConfig: DecodingConfig

    private var audioBuffer: MLXArray
    private var decoderHidden: (MLXArray, MLXArray)?
    private var lastToken: Int?
    private var cleanTokens: [AlignedToken] = []
    private var dirtyTokens: [AlignedToken] = []
    private var cache: [ConformerCache]

    public init(
        model: ParakeetTDT,
        contextSize: (Int, Int),
        depth: Int = 1,
        decodingConfig: DecodingConfig = DecodingConfig()
    ) {
        self.model = model
        self.contextSize = contextSize
        self.depth = depth
        self.decodingConfig = decodingConfig

        self.audioBuffer = MLXArray([])
        self.cache = Array(
            repeating: RotatingConformerCache(
                contextSize: contextSize.0,
                cacheDropSize: contextSize.1 * depth
            ), count: model.encoderConfig.nLayers)
    }

    public var dropSize: Int {
        contextSize.1 * depth
    }

    public var result: AlignedResult {
        sentencesToResult(tokensToSentences(cleanTokens + dirtyTokens))
    }

    public func addAudio(_ audio: MLXArray) throws {
        // Concatenate new audio to buffer
        audioBuffer = MLX.concatenated([audioBuffer, audio], axis: 0)

        // Get mel spectrogram
        let mel = try getLogMel(audioBuffer, config: model.preprocessConfig)

        // Process through encoder with cache
        let (features, lengths) = model.encode(mel, cache: cache)
        let length = Int(lengths[0].item(Int32.self))

        // Update audio buffer to keep only recent samples
        let samplesToKeep =
            dropSize * model.encoderConfig.subsamplingFactor * model.preprocessConfig.hopLength
        if audioBuffer.shape[0] > samplesToKeep {
            audioBuffer = audioBuffer[(audioBuffer.shape[0] - samplesToKeep)...]
        }

        // Decode clean region (won't be dropped)
        let cleanLength = max(0, length - dropSize)

        if cleanLength > 0 {
            let (cleanResult, cleanState) = try model.decode(
                features: features[0..., 0..<cleanLength],
                lengths: MLXArray([cleanLength]),
                lastToken: lastToken.map { [$0] },
                hiddenState: decoderHidden.map { [$0] },
                config: decodingConfig
            )

            decoderHidden = cleanState[0]
            lastToken = cleanResult[0].last?.id
            cleanTokens.append(contentsOf: cleanResult[0])
        }

        // Decode dirty region (will be dropped on next iteration)
        if length > cleanLength {
            let (dirtyResult, _) = try model.decode(
                features: features[0..., cleanLength...],
                lengths: MLXArray([Int(length - cleanLength)]),
                lastToken: lastToken.map { [$0] },
                hiddenState: decoderHidden.map { [$0] },
                config: decodingConfig
            )

            dirtyTokens = dirtyResult[0]
        }
    }
}

extension ParakeetTDT {
    public func transcribeStream(
        contextSize: (Int, Int) = (256, 256),
        depth: Int = 1
    ) -> StreamingParakeet {
        return StreamingParakeet(
            model: self,
            contextSize: contextSize,
            depth: depth
        )
    }
}
#endif

import Foundation
#if arch(arm64)
import MLX

// MARK: - Configuration Structures

nonisolated public struct PreprocessConfig: Codable {
    public let sampleRate: Int
    public let normalize: String
    public let windowSize: Float
    public let windowStride: Float
    public let window: String
    public let features: Int
    public let nFFT: Int
    public let dither: Float
    public let padTo: Int
    public let padValue: Float
    public let preemph: Float?
    public let magPower: Float = 2.0

    public var winLength: Int { Int(windowSize * Float(sampleRate)) }
    public var hopLength: Int { Int(windowStride * Float(sampleRate)) }

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case normalize
        case windowSize = "window_size"
        case windowStride = "window_stride"
        case window
        case features
        case nFFT = "n_fft"
        case dither
        case padTo = "pad_to"
        case padValue = "pad_value"
        case preemph
        case magPower = "mag_power"
    }
}

nonisolated public struct ConformerConfig: Codable {
    public let featIn: Int
    public let nLayers: Int
    public let dModel: Int
    public let nHeads: Int
    public let ffExpansionFactor: Int
    public let subsamplingFactor: Int
    public let selfAttentionModel: String
    public let subsampling: String
    public let convKernelSize: Int
    public let subsamplingConvChannels: Int
    public let posEmbMaxLen: Int
    public let causalDownsampling: Bool = false
    public let useBias: Bool = true
    public let xscaling: Bool = false
    public let subsamplingConvChunkingFactor: Int = 1
    public let attContextSize: [Int]?
    public let posBiasU: [Float]?
    public let posBiasV: [Float]?

    public func posBiasUArray() -> MLXArray? { posBiasU.map { MLXArray($0) } }
    public func posBiasVArray() -> MLXArray? { posBiasV.map { MLXArray($0) } }

    enum CodingKeys: String, CodingKey {
        case featIn = "feat_in"
        case nLayers = "n_layers"
        case dModel = "d_model"
        case nHeads = "n_heads"
        case ffExpansionFactor = "ff_expansion_factor"
        case subsamplingFactor = "subsampling_factor"
        case selfAttentionModel = "self_attention_model"
        case subsampling
        case convKernelSize = "conv_kernel_size"
        case subsamplingConvChannels = "subsampling_conv_channels"
        case posEmbMaxLen = "pos_emb_max_len"
        case causalDownsampling = "causal_downsampling"
        case useBias = "use_bias"
        case xscaling
        case subsamplingConvChunkingFactor = "subsampling_conv_chunking_factor"
        case attContextSize = "att_context_size"
        case posBiasU = "pos_bias_u"
        case posBiasV = "pos_bias_v"
    }
}

nonisolated public struct PredictNetworkConfig: Codable {
    public let predHidden: Int
    public let predRNNLayers: Int
    public let rnnHiddenSize: Int?

    enum CodingKeys: String, CodingKey {
        case predHidden = "pred_hidden"
        case predRNNLayers = "pred_rnn_layers"
        case rnnHiddenSize = "rnn_hidden_size"
    }
}

nonisolated public struct JointNetworkConfig: Codable {
    public let jointHidden: Int
    public let activation: String
    public let encoderHidden: Int
    public let predHidden: Int

    enum CodingKeys: String, CodingKey {
        case jointHidden = "joint_hidden"
        case activation
        case encoderHidden = "encoder_hidden"
        case predHidden = "pred_hidden"
    }
}

nonisolated public struct PredictConfig: Codable {
    public let blankAsPad: Bool
    public let vocabSize: Int
    public let prednet: PredictNetworkConfig

    enum CodingKeys: String, CodingKey {
        case blankAsPad = "blank_as_pad"
        case vocabSize = "vocab_size"
        case prednet
    }
}

nonisolated public struct JointConfig: Codable {
    public let numClasses: Int
    public let vocabulary: [String]
    public let jointnet: JointNetworkConfig
    public let numExtraOutputs: Int

    enum CodingKeys: String, CodingKey {
        case numClasses = "num_classes"
        case vocabulary
        case jointnet
        case numExtraOutputs = "num_extra_outputs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numClasses = try container.decode(Int.self, forKey: .numClasses)
        vocabulary = try container.decode([String].self, forKey: .vocabulary)
        jointnet = try container.decode(JointNetworkConfig.self, forKey: .jointnet)
        numExtraOutputs = try container.decodeIfPresent(Int.self, forKey: .numExtraOutputs) ?? 0
    }
}

nonisolated public struct TDTDecodingConfig: Codable {
    public let modelType: String
    public let durations: [Int]
    public let greedy: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case durations
        case greedy
    }

    public init(modelType: String, durations: [Int], greedy: [String: Any]? = nil) {
        self.modelType = modelType
        self.durations = durations
        self.greedy = greedy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decode(String.self, forKey: .modelType)
        durations = try container.decode([Int].self, forKey: .durations)

        if container.contains(.greedy) {
            greedy = try container.decode([String: Int].self, forKey: .greedy)
        } else {
            greedy = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(durations, forKey: .durations)
        if let greedy = greedy {
            try container.encode(greedy as? [String: Int], forKey: .greedy)
        }
    }
}

nonisolated public struct ParakeetTDTConfig: Codable {
    public let preprocessor: PreprocessConfig
    public let encoder: ConformerConfig
    public let decoder: PredictConfig
    public let joint: JointConfig
    public let decoding: TDTDecodingConfig
}

// MARK: - Alignment Structures

nonisolated public struct AlignedToken: Sendable {
    public let id: Int
    public var start: Float
    public var duration: Float
    public let text: String

    public var end: Float {
        get { start + duration }
        set { duration = newValue - start }
    }

    public init(id: Int, start: Float, duration: Float, text: String) {
        self.id = id
        self.start = start
        self.duration = duration
        self.text = text
    }
}

nonisolated public struct AlignedSentence: Sendable {
    public let tokens: [AlignedToken]
    public let start: Float
    public let end: Float

    public var text: String { tokens.map { $0.text }.joined() }

    public init(tokens: [AlignedToken]) {
        self.tokens = tokens
        self.start = tokens.first?.start ?? 0.0
        self.end = tokens.last?.end ?? 0.0
    }
}

nonisolated public struct AlignedResult: Sendable {
    public let sentences: [AlignedSentence]

    public var text: String { sentences.map { $0.text }.joined(separator: " ") }

    public init(sentences: [AlignedSentence]) {
        self.sentences = sentences
    }
}

// MARK: - Decoding Configuration

nonisolated public struct DecodingConfig {
    public let decoding: String

    public init(decoding: String = "greedy") {
        self.decoding = decoding
    }
}
#endif

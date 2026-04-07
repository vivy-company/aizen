import Foundation
#if arch(arm64)
import MLX

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
            ),
            count: model.encoderConfig.nLayers
        )
    }

    public var dropSize: Int {
        contextSize.1 * depth
    }

    public var result: AlignedResult {
        sentencesToResult(tokensToSentences(cleanTokens + dirtyTokens))
    }

    public func addAudio(_ audio: MLXArray) throws {
        audioBuffer = MLX.concatenated([audioBuffer, audio], axis: 0)

        let mel = try getLogMel(audioBuffer, config: model.preprocessConfig)
        let (features, lengths) = model.encode(mel, cache: cache)
        let length = Int(lengths[0].item(Int32.self))

        let samplesToKeep =
            dropSize * model.encoderConfig.subsamplingFactor * model.preprocessConfig.hopLength
        if audioBuffer.shape[0] > samplesToKeep {
            audioBuffer = audioBuffer[(audioBuffer.shape[0] - samplesToKeep)...]
        }

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
        StreamingParakeet(
            model: self,
            contextSize: contextSize,
            depth: depth
        )
    }
}
#endif

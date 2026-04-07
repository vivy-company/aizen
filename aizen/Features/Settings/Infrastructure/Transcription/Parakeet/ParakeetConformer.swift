import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Feed Forward Network

@preconcurrency nonisolated public class FeedForward: Module {
    let linear1: Linear
    let linear2: Linear
    let activation: SiLU

    public init(dModel: Int, dFF: Int, useBias: Bool = true) {
        self.linear1 = Linear(dModel, dFF, bias: useBias)
        self.linear2 = Linear(dFF, dModel, bias: useBias)
        self.activation = SiLU()
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return linear2(self.activation(linear1(x)))
    }
}

// MARK: - Convolution Module

@preconcurrency nonisolated public class ConformerConvolution: Module {
    let padding: Int
    let pointwiseConv1: Conv1d
    let depthwiseConv: Conv1d
    let batchNorm: BatchNorm
    let pointwiseConv2: Conv1d
    let activation: SiLU

    public init(config: ConformerConfig) {
        assert((config.convKernelSize - 1) % 2 == 0)

        self.padding = (config.convKernelSize - 1) / 2

        self.pointwiseConv1 = Conv1d(
            inputChannels: config.dModel,
            outputChannels: config.dModel * 2,
            kernelSize: 1,
            stride: 1,
            padding: 0,
            bias: config.useBias
        )

        self.depthwiseConv = Conv1d(
            inputChannels: config.dModel,
            outputChannels: config.dModel,
            kernelSize: config.convKernelSize,
            stride: 1,
            padding: 0,
            groups: config.dModel,
            bias: config.useBias
        )

        self.batchNorm = BatchNorm(featureCount: config.dModel)
        self.activation = SiLU()
        self.pointwiseConv2 = Conv1d(
            inputChannels: config.dModel,
            outputChannels: config.dModel,
            kernelSize: 1,
            stride: 1,
            padding: 0,
            bias: config.useBias
        )

        super.init()
    }

    public func callAsFunction(_ x: MLXArray, cache: ConformerCache? = nil) -> MLXArray {
        var x = x

        x = self.pointwiseConv1(x)
        x = MLXNN.glu(x, axis: 2)

        // Handle caching for convolution if provided
        if let cache = cache {
            x = cache.updateAndFetchConv(x, padding: padding)
        } else {
            // Match Python exactly: mx.pad(x, ((0, 0), (self.padding, self.padding), (0, 0)))
            x = MLX.padded(
                x,
                widths: [(0, 0), (padding, padding), (0, 0)].map { IntOrPair($0) },
                mode: .constant,
                value: MLXArray(0.0)
            )
        }

        x = depthwiseConv(x)
        x = batchNorm(x)
        x = self.activation(x)
        x = self.pointwiseConv2(x)

        return x
    }
}

@preconcurrency nonisolated public class Conformer: Module {
    let config: ConformerConfig
    let posEnc: Module?
    let preEncode: Module
    let layers: [ConformerBlock]

    public init(config: ConformerConfig) {
        self.config = config

        // Initialize positional encoding based on attention model
        switch config.selfAttentionModel {
        case "rel_pos":
            self.posEnc = RelPositionalEncoding(
                dModel: config.dModel,
                maxLen: config.posEmbMaxLen,
                scaleInput: config.xscaling
            )
        case "rel_pos_local_attn":
            self.posEnc = LocalRelPositionalEncoding(
                dModel: config.dModel,
                maxLen: config.posEmbMaxLen,
                scaleInput: config.xscaling
            )
        default:
            self.posEnc = nil
        }

        // Initialize pre-encoding layer
        if config.subsamplingFactor > 1 {
            if config.subsampling == "dw_striding" && !config.causalDownsampling {
                self.preEncode = DwStridingSubsampling(config: config)
            } else {
                fatalError("Other subsampling methods not implemented yet!")
            }
        } else {
            self.preEncode = Linear(config.featIn, config.dModel)
        }

        // Initialize conformer blocks
        self.layers = (0..<config.nLayers).map { _ in ConformerBlock(config: config) }

        super.init()
    }

    public func callAsFunction(
        _ x: MLXArray,
        lengths: MLXArray? = nil,
        cache: [ConformerCache?]? = nil
    ) -> (MLXArray, MLXArray) {

        let actualLengths = lengths ?? MLXArray(Array(repeating: x.shape[1], count: x.shape[0]))
        let actualCache = cache ?? Array(repeating: nil, count: layers.count)

        var x = x
        var outLengths = actualLengths

        // Pre-encoding
        if let dwSubsampling = preEncode as? DwStridingSubsampling {
            (x, outLengths) = dwSubsampling(x, lengths: actualLengths)
        } else if let linear = preEncode as? Linear {
            x = linear(x)
        } else {
            fatalError("Non-implemented pre-encoding layer type!")
        }

        // Positional encoding
        var posEmb: MLXArray?
        if let posEncLayer = posEnc as? RelPositionalEncoding {
            let offset = actualCache[0]?.offset ?? 0
            (x, posEmb) = posEncLayer(x, offset: offset)
        } else if let localPosEncLayer = posEnc as? LocalRelPositionalEncoding {
            let offset = actualCache[0]?.offset ?? 0
            (x, posEmb) = localPosEncLayer(x, offset: offset)
        }

        // Apply conformer blocks
        for (_, (layer, cache)) in zip(layers, actualCache).enumerated() {
            x = layer(x, posEmb: posEmb, cache: cache)
            let xAfter = x.max().item(Float.self)

            if xAfter.isInfinite {
                break
            }
        }

        return (x, outLengths)
    }

    public func setAttentionModel(
        _ name: String,
        contextSize: (Int, Int)? = (256, 256)
    ) {
        // Update positional encoding
        switch name {
        case "rel_pos":
            // Would need to replace posEnc with RelPositionalEncoding
            break
        case "rel_pos_local_attn":
            // Would need to replace posEnc with LocalRelPositionalEncoding
            break
        default:
            // Set to no positional encoding
            break
        }

        // Update attention in all layers
        for layer in layers {
            layer.setAttentionModel(name, contextSize: contextSize)
        }
    }
}

// MARK: - Cache Classes (simplified)

nonisolated public class ConformerCache {
    public var offset: Int = 0

    public init() {}

    public func updateAndFetchConv(_ x: MLXArray, padding: Int) -> MLXArray {
        // Simplified cache implementation
        let padArray = Array(repeating: (0, 0), count: x.ndim)
        var padArray2 = padArray
        padArray2[1] = (padding, padding)
        return MLX.padded(
            x, widths: padArray2.map { IntOrPair($0) }, mode: .constant, value: MLXArray(0.0))
    }
}

nonisolated public class RotatingConformerCache: ConformerCache {
    let contextSize: Int
    let cacheDropSize: Int

    public init(contextSize: Int, cacheDropSize: Int) {
        self.contextSize = contextSize
        self.cacheDropSize = cacheDropSize
        super.init()
    }
}

#endif

import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Conformer Block

@preconcurrency nonisolated public class ConformerBlock: Module {
    let config: ConformerConfig
    let normFeedForward1: LayerNorm
    let feedForward1: FeedForward
    let normSelfAtt: LayerNorm
    var selfAttn: Module
    let normConv: LayerNorm
    let conv: ConformerConvolution
    let normFeedForward2: LayerNorm
    let feedForward2: FeedForward
    let normOut: LayerNorm

    public init(config: ConformerConfig) {
        self.config = config
        let ffHiddenDim = config.dModel * config.ffExpansionFactor

        self.normFeedForward1 = LayerNorm(dimensions: config.dModel)
        self.feedForward1 = FeedForward(
            dModel: config.dModel, dFF: ffHiddenDim, useBias: config.useBias)

        self.normSelfAtt = LayerNorm(dimensions: config.dModel)

        switch config.selfAttentionModel {
        case "rel_pos":
            self.selfAttn = RelPositionMultiHeadAttention(
                nHeads: config.nHeads,
                nFeat: config.dModel,
                bias: config.useBias,
                posBiasU: config.posBiasUArray(),
                posBiasV: config.posBiasVArray()
            )
        case "rel_pos_local_attn":
            let contextSize = config.attContextSize ?? [-1, -1]
            guard contextSize.count >= 2 else {
                fatalError("Invalid Context Size config")
            }
            self.selfAttn = RelPositionMultiHeadLocalAttention(
                nHeads: config.nHeads,
                nFeat: config.dModel,
                bias: config.useBias,
                posBiasU: config.posBiasUArray(),
                posBiasV: config.posBiasVArray(),
                contextSize: (contextSize[0], contextSize[1])
            )
        default:
            self.selfAttn = MultiHeadAttention(
                nHeads: config.nHeads,
                nFeat: config.dModel,
                bias: true
            )
        }

        self.normConv = LayerNorm(dimensions: config.dModel)
        self.conv = ConformerConvolution(config: config)
        self.normFeedForward2 = LayerNorm(dimensions: config.dModel)
        self.feedForward2 = FeedForward(
            dModel: config.dModel, dFF: ffHiddenDim, useBias: config.useBias)
        self.normOut = LayerNorm(dimensions: config.dModel)

        super.init()
    }

    public func callAsFunction(
        _ x: MLXArray,
        posEmb: MLXArray? = nil,
        mask: MLXArray? = nil,
        cache: ConformerCache? = nil
    ) -> MLXArray {

        var x = x
        x = x + 0.5 * feedForward1(normFeedForward1(x))

        let xNorm = normSelfAtt(x)
        let attentionOut: MLXArray

        if let relAttn = selfAttn as? RelPositionMultiHeadAttention {
            attentionOut = relAttn(
                xNorm,
                xNorm,
                xNorm,
                posEmb: posEmb,
                mask: mask,
                cache: cache
            )
        } else if let localAttn = selfAttn as? RelPositionMultiHeadLocalAttention {
            attentionOut = localAttn(
                xNorm,
                xNorm,
                xNorm,
                posEmb: posEmb,
                mask: mask,
                cache: cache
            )
        } else if let standardAttn = selfAttn as? MultiHeadAttention {
            attentionOut = standardAttn(xNorm, xNorm, xNorm, mask: mask)
        } else {
            fatalError("Unknown attention type")
        }

        x = x + attentionOut
        x = x + conv(normConv(x), cache: cache)
        x = x + 0.5 * feedForward2(normFeedForward2(x))

        return normOut(x)
    }

    public func setAttentionModel(
        _ name: String,
        contextSize: (Int, Int)? = (256, 256)
    ) {
        let newAttn: Module

        switch name {
        case "rel_pos":
            newAttn = RelPositionMultiHeadAttention(
                nHeads: self.config.nHeads,
                nFeat: self.config.dModel,
                bias: self.config.useBias,
                posBiasU: self.config.posBiasUArray(),
                posBiasV: self.config.posBiasVArray()
            )
        case "rel_pos_local_attn":
            newAttn = RelPositionMultiHeadLocalAttention(
                nHeads: self.config.nHeads,
                nFeat: self.config.dModel,
                bias: self.config.useBias,
                posBiasU: self.config.posBiasUArray(),
                posBiasV: self.config.posBiasVArray(),
                contextSize: contextSize ?? (256, 256)
            )
        case "normal":
            newAttn = MultiHeadAttention(
                nHeads: self.config.nHeads,
                nFeat: self.config.dModel,
                bias: true
            )
        default:
            fatalError("Unknown attention model: \(name)")
        }

        newAttn.update(parameters: self.selfAttn.parameters())
        self.selfAttn = newAttn
    }
}
#endif

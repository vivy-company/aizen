import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Multi-Head Attention

@preconcurrency nonisolated public class MultiHeadAttention: Module {
    let nHeads: Int
    let nFeat: Int
    let headDim: Int
    let scale: Float

    let linearQ: Linear
    let linearK: Linear
    let linearV: Linear
    let linearOut: Linear

    public init(nHeads: Int, nFeat: Int, bias: Bool = true) {
        self.nHeads = nHeads
        self.nFeat = nFeat
        self.headDim = nFeat / nHeads
        self.scale = 1.0 / sqrt(Float(headDim))

        self.linearQ = Linear(nFeat, nFeat, bias: bias)
        self.linearK = Linear(nFeat, nFeat, bias: bias)
        self.linearV = Linear(nFeat, nFeat, bias: bias)
        self.linearOut = Linear(nFeat, nFeat, bias: bias)

        super.init()
    }

    public func callAsFunction(
        _ q: MLXArray,
        _ k: MLXArray,
        _ v: MLXArray,
        posEmb: MLXArray? = nil,
        mask: MLXArray? = nil,
        cache: ConformerCache? = nil
    ) -> MLXArray {
        let q = linearQ(q)
        let k = linearK(k)
        let v = linearV(v)

        let batch = q.shape[0]
        let qSeq = q.shape[1]
        let kSeq = k.shape[1]

        let qReshaped = q.reshaped([batch, qSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        let kReshaped = k.reshaped([batch, kSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        let vReshaped = v.reshaped([batch, kSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])

        // if let cache = cache {
        //     k, v = cache.updateAndFetchConv(k, v)
        // }

        let o = MLX.scaledDotProductAttention(
            queries: qReshaped,
            keys: kReshaped,
            values: vReshaped,
            scale: scale,
            mask: mask
        )

        let output = o.transposed(axes: [0, 2, 1, 3]).reshaped([batch, qSeq, nFeat])

        return linearOut(output)
    }
}

#endif

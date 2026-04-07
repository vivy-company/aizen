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

// MARK: - Relative Position Multi-Head Attention

@preconcurrency nonisolated public class RelPositionMultiHeadAttention: MultiHeadAttention {
    var linearPos: Linear
    public var posBiasU: MLXArray
    public var posBiasV: MLXArray

    public init(
        nHeads: Int,
        nFeat: Int,
        bias: Bool = true,
        posBiasU: MLXArray? = nil,
        posBiasV: MLXArray? = nil
    ) {
        // Initialize properties before calling super.init()
        self.linearPos = Linear(nFeat, nFeat, bias: false)

        if let posBiasU = posBiasU {
            self.posBiasU = posBiasU
        } else {
            self.posBiasU = MLXArray.zeros([nHeads, nFeat / nHeads])
        }

        if let posBiasV = posBiasV {
            self.posBiasV = posBiasV
        } else {
            self.posBiasV = MLXArray.zeros([nHeads, nFeat / nHeads])
        }

        super.init(nHeads: nHeads, nFeat: nFeat, bias: bias)
    }

    private func relShift(_ x: MLXArray) -> MLXArray {
        let B = x.shape[0]
        let H = x.shape[1]
        let Tq = x.shape[2]
        let posLen = x.shape[3]

        // Pad on the last dimension: (0, 0), (0, 0), (0, 0), (1, 0)
        let padded = MLX.padded(
            x,
            widths: [(0, 0), (0, 0), (0, 0), (1, 0)].map { IntOrPair($0) },
            mode: .constant,
            value: MLXArray(0.0)
        )

        let reshaped = padded.reshaped([B, H, posLen + 1, Tq])
        let sliced = reshaped[0..., 0..., 1..., 0...]
        let result = sliced.reshaped([B, H, Tq, posLen])

        return result
    }

    override public func callAsFunction(
        _ q: MLXArray,
        _ k: MLXArray,
        _ v: MLXArray,
        posEmb: MLXArray? = nil,
        mask: MLXArray? = nil,
        cache: ConformerCache? = nil
    ) -> MLXArray {
        guard let posEmb = posEmb else {
            fatalError("pos_emb is necessary for RelPositionMultiHeadAttention!")
        }

        let q = linearQ(q)
        let k = linearK(k)
        let v = linearV(v)
        let p = linearPos(posEmb)  // p stands for position

        let batch = q.shape[0]
        let qSeq = q.shape[1]
        let kSeq = k.shape[1]
        let posLen = p.shape[1]

        let qReshaped = q.reshaped([batch, qSeq, nHeads, headDim])
        let qU = (qReshaped + posBiasU).transposed(axes: [0, 2, 1, 3])
        let qV = (qReshaped + posBiasV).transposed(axes: [0, 2, 1, 3])

        let kReshaped = k.reshaped([batch, kSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        let vReshaped = v.reshaped([batch, kSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        let pReshaped = p.reshaped([batch, posLen, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])

        // if let cache = cache {
        //     k, v = cache.update_and_fetch_kv(k, v)
        // }

        let matrixBD = MLX.matmul(qV, pReshaped.swappedAxes(-2, -1))
        let matrixBDShifted = self.relShift(matrixBD)

        // Match Python exactly: matrix_bd[:, :, :, : k.shape[-2]] * self.scale
        // k.shape[-2] is the sequence length dimension
        let kSeqLen = kReshaped.shape[2]  // sequence length dimension

        // Add bounds checking to prevent crash
        let matrixBDLastDim = matrixBDShifted.shape[3]
        guard kSeqLen <= matrixBDLastDim else {
            fatalError(
                "kSeqLen (\(kSeqLen)) > matrixBDLastDim (\(matrixBDLastDim)). Shapes: matrixBDShifted=\(matrixBDShifted.shape), kReshaped=\(kReshaped.shape)"
            )
        }

        let matrixBDScaled = matrixBDShifted[0..., 0..., 0..., 0..<kSeqLen] * scale

        var finalMatrixBD = matrixBDScaled
        if let mask = mask {
            let expandedMask = mask.expandedDimensions(axis: 0)
            finalMatrixBD = MLX.which(expandedMask, MLXArray(-Float.infinity), finalMatrixBD)
        }

        let o = MLX.scaledDotProductAttention(
            queries: qU,
            keys: kReshaped,
            values: vReshaped,
            scale: scale,
            mask: finalMatrixBD
        )

        let output = o.transposed(axes: [0, 2, 1, 3]).reshaped([batch, qSeq, -1])

        return linearOut(output)
    }
}

#endif

import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

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
        self.linearPos = Linear(nFeat, nFeat, bias: false)

        if let posBiasU {
            self.posBiasU = posBiasU
        } else {
            self.posBiasU = MLXArray.zeros([nHeads, nFeat / nHeads])
        }

        if let posBiasV {
            self.posBiasV = posBiasV
        } else {
            self.posBiasV = MLXArray.zeros([nHeads, nFeat / nHeads])
        }

        super.init(nHeads: nHeads, nFeat: nFeat, bias: bias)
    }

    nonisolated private func relShift(_ x: MLXArray) -> MLXArray {
        let batch = x.shape[0]
        let heads = x.shape[1]
        let targetLength = x.shape[2]
        let positionLength = x.shape[3]

        let padded = MLX.padded(
            x,
            widths: [(0, 0), (0, 0), (0, 0), (1, 0)].map { IntOrPair($0) },
            mode: .constant,
            value: MLXArray(0.0)
        )

        let reshaped = padded.reshaped([batch, heads, positionLength + 1, targetLength])
        let sliced = reshaped[0..., 0..., 1..., 0...]
        return sliced.reshaped([batch, heads, targetLength, positionLength])
    }

    override public func callAsFunction(
        _ q: MLXArray,
        _ k: MLXArray,
        _ v: MLXArray,
        posEmb: MLXArray? = nil,
        mask: MLXArray? = nil,
        cache: ConformerCache? = nil
    ) -> MLXArray {
        guard let posEmb else {
            fatalError("pos_emb is necessary for RelPositionMultiHeadAttention!")
        }

        let q = linearQ(q)
        let k = linearK(k)
        let v = linearV(v)
        let p = linearPos(posEmb)

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

        let matrixBD = MLX.matmul(qV, pReshaped.swappedAxes(-2, -1))
        let matrixBDShifted = self.relShift(matrixBD)

        let kSeqLen = kReshaped.shape[2]
        let matrixBDLastDim = matrixBDShifted.shape[3]
        guard kSeqLen <= matrixBDLastDim else {
            fatalError(
                "kSeqLen (\(kSeqLen)) > matrixBDLastDim (\(matrixBDLastDim)). Shapes: matrixBDShifted=\(matrixBDShifted.shape), kReshaped=\(kReshaped.shape)"
            )
        }

        let matrixBDScaled = matrixBDShifted[0..., 0..., 0..., 0..<kSeqLen] * scale

        var finalMatrixBD = matrixBDScaled
        if let mask {
            let expandedMask = mask.expandedDimensions(axis: 0)
            finalMatrixBD = MLX.which(expandedMask, MLXArray(-Float.infinity), finalMatrixBD)
        }

        let output = MLX.scaledDotProductAttention(
            queries: qU,
            keys: kReshaped,
            values: vReshaped,
            scale: scale,
            mask: finalMatrixBD
        )

        return linearOut(output.transposed(axes: [0, 2, 1, 3]).reshaped([batch, qSeq, -1]))
    }
}

#endif

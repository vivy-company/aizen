import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

@preconcurrency nonisolated public class RelPositionMultiHeadLocalAttention: RelPositionMultiHeadAttention {
    var contextSize: (Int, Int)

    public init(
        nHeads: Int,
        nFeat: Int,
        bias: Bool = true,
        posBiasU: MLXArray? = nil,
        posBiasV: MLXArray? = nil,
        contextSize: (Int, Int) = (256, 256)
    ) {
        self.contextSize = contextSize

        super.init(
            nHeads: nHeads,
            nFeat: nFeat,
            bias: bias,
            posBiasU: posBiasU,
            posBiasV: posBiasV
        )

        if min(contextSize.0, contextSize.1) <= 0 {
            fatalError("Context size for RelPositionMultiHeadLocalAttention must be > 0.")
        }
    }

    public override func callAsFunction(
        _ q: MLXArray,
        _ k: MLXArray,
        _ v: MLXArray,
        posEmb: MLXArray? = nil,
        mask: MLXArray? = nil,
        cache: ConformerCache? = nil
    ) -> MLXArray {
        guard let posEmb = posEmb else {
            fatalError("pos_emb is necessary for RelPositionMultiHeadLocalAttention!")
        }

        let originalQSeq = q.shape[1]

        var actualMask = mask
        if actualMask == nil {
            actualMask = MLXArray.zeros([q.shape[0], q.shape[1]]).asType(.bool)
        }

        let q = linearQ(q)
        let k = linearK(k)
        let v = linearV(v)
        let p = linearPos(posEmb)

        let batch = q.shape[0]
        let qSeq = q.shape[1]
        let kSeq = k.shape[1]
        let posLen = p.shape[1]

        var qReshaped = q.reshaped([batch, qSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        var kReshaped = k.reshaped([batch, kSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        var vReshaped = v.reshaped([batch, kSeq, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])
        let pReshaped = p.reshaped([batch, posLen, nHeads, headDim]).transposed(axes: [0, 2, 1, 3])

        let w = max(contextSize.0, contextSize.1)
        let padLen = (2 * w - qReshaped.shape[2] % (2 * w)) % (2 * w)

        qReshaped = MLX.padded(
            qReshaped,
            widths: [(0, 0), (0, 0), (0, padLen), (0, 0)].map { IntOrPair($0) },
            mode: .constant,
            value: MLXArray(0.0)
        )

        kReshaped = MLX.padded(
            kReshaped,
            widths: [(0, 0), (0, 0), (0, padLen), (0, 0)].map { IntOrPair($0) },
            mode: .constant,
            value: MLXArray(0.0)
        )

        vReshaped = MLX.padded(
            vReshaped,
            widths: [(0, 0), (0, 0), (0, padLen), (0, 0)].map { IntOrPair($0) },
            mode: .constant,
            value: MLXArray(0.0)
        )

        actualMask = MLX.padded(
            actualMask!,
            widths: [(0, 0), (0, padLen)].map { IntOrPair($0) },
            mode: .constant,
            value: MLXArray(true)
        )

        let qU = qReshaped + posBiasU.expandedDimensions(axis: 1)
        let qV = qReshaped + posBiasV.expandedDimensions(axis: 1)

        let matrixAC = self.matmulQK(qU, kReshaped, w: w)
        let matrixBD = MLX.matmul(qV, pReshaped.swappedAxes(-2, -1))

        let matrixACLastDim = matrixAC.shape[3]
        let matrixBDLastDim = matrixBD.shape[3]
        let leftContextSize = min(contextSize.0, matrixACLastDim, matrixBDLastDim)

        if leftContextSize > 0 {
            matrixAC[0..., 0..., 0..., 0..<leftContextSize] =
                matrixAC[0..., 0..., 0..., 0..<leftContextSize]
                + matrixBD[0..., 0..., 0..., 0..<leftContextSize]
        }

        let rightStartIdx = max(0, 2 * w + 1 - (contextSize.1 + 1))
        let rightContextStart = min(contextSize.0, matrixBDLastDim)

        if rightStartIdx < matrixACLastDim && rightContextStart < matrixBDLastDim {
            matrixAC[0..., 0..., 0..., rightStartIdx...] =
                matrixAC[0..., 0..., 0..., rightStartIdx...]
                + matrixBD[0..., 0..., 0..., rightContextStart...]
        }

        let leftMaskEnd = min(w - contextSize.0, matrixACLastDim)
        let rightMaskStart = min(w + contextSize.1 + 1, matrixACLastDim)

        if leftMaskEnd > 0 {
            matrixAC[0..., 0..., 0..., 0..<leftMaskEnd] = MLXArray(-Float.infinity)
        }
        if rightMaskStart < matrixACLastDim {
            matrixAC[0..., 0..., 0..., rightMaskStart...] = MLXArray(-Float.infinity)
        }

        let scores = matrixAC * scale
        let mask = actualMask!.expandedDimensions(axis: 1).expandedDimensions(axis: -1)
        let floatMask = MLX.which(mask, MLXArray(-Float.infinity), MLXArray(0.0)).asType(matrixAC.dtype)
        let ones = MLXArray.ones(like: floatMask)
        let dMask = self.matmulQK(ones, floatMask, w: w)

        let finalScores = scores + dMask
        let attn = MLX.softmax(finalScores, axis: -1)
        let maskedAttn = MLX.which(mask, MLXArray(0.0), attn)
        let out = self.matmulPV(maskedAttn, vReshaped, w: w)

        let reshapedOut = out.reshaped([batch, -1, nHeads * headDim])
        let actualSeqLen = min(originalQSeq, reshapedOut.shape[1])
        let output = reshapedOut[0..., 0..<actualSeqLen]

        return linearOut(output)
    }
}
#endif

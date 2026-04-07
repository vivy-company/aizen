import Foundation
#if arch(arm64)
import MLX
import MLXNN

nonisolated final class WhisperMultiHeadAttention: Module {
    let nHead: Int
    let query: Linear
    let key: Linear
    let value: Linear
    let out: Linear

    init(nState: Int, nHead: Int) {
        self.nHead = nHead
        self.query = Linear(nState, nState)
        self.key = Linear(nState, nState, bias: false)
        self.value = Linear(nState, nState)
        self.out = Linear(nState, nState)
        super.init()
    }

    override func items() -> ModuleItems {
        NestedDictionary(values: [
            "query": .value(.module(query)),
            "key": .value(.module(key)),
            "value": .value(.module(value)),
            "out": .value(.module(out))
        ])
    }

    func callAsFunction(
        _ x: MLXArray,
        xa: MLXArray? = nil,
        mask: MLXArray? = nil,
        kvCache: WhisperKVCache? = nil
    ) -> (MLXArray, WhisperKVCache) {
        let q = query(x)
        var k: MLXArray
        var v: MLXArray

        if let xa {
            if let kvCache {
                k = kvCache.key
                v = kvCache.value
            } else {
                k = key(xa)
                v = value(xa)
            }
        } else {
            k = key(x)
            v = value(x)
            if let kvCache {
                k = concatenated([kvCache.key, k], axis: 1)
                v = concatenated([kvCache.value, v], axis: 1)
            }
        }

        let (wv, _) = qkvAttention(q: q, k: k, v: v, mask: mask)
        let output = out(wv)
        return (output, WhisperKVCache(key: k, value: v))
    }

    private func qkvAttention(q: MLXArray, k: MLXArray, v: MLXArray, mask: MLXArray?) -> (MLXArray, MLXArray) {
        let batch = q.dim(0)
        let nCtx = q.dim(1)
        let nState = q.dim(2)
        let headDim = nState / nHead

        let scale = pow(Float(headDim), -0.25)
        let q = q.reshaped(batch, nCtx, nHead, headDim).transposed(0, 2, 1, 3) * scale
        let k = k.reshaped(batch, k.dim(1), nHead, headDim).transposed(0, 2, 3, 1) * scale
        let v = v.reshaped(batch, v.dim(1), nHead, headDim).transposed(0, 2, 1, 3)

        var qk = matmul(q, k)
        if let mask {
            let maskSlice = mask[0 ..< nCtx, 0 ..< nCtx]
            qk = qk + maskSlice
        }

        let w = softmax(qk, axis: -1, precise: true)
        let out = matmul(w, v).transposed(0, 2, 1, 3).reshaped(batch, nCtx, nState)
        return (out, qk)
    }
}

#endif

import Foundation
#if arch(arm64)
import MLX
import MLXNN

nonisolated final class WhisperDecoderBlock: Module {
    let attn: WhisperMultiHeadAttention
    let attnLn: LayerNorm
    let crossAttn: WhisperMultiHeadAttention
    let crossAttnLn: LayerNorm
    let mlp1: Linear
    let mlp2: Linear
    let mlpLn: LayerNorm

    init(nState: Int, nHead: Int) {
        self.attn = WhisperMultiHeadAttention(nState: nState, nHead: nHead)
        self.attnLn = LayerNorm(dimensions: nState)
        self.crossAttn = WhisperMultiHeadAttention(nState: nState, nHead: nHead)
        self.crossAttnLn = LayerNorm(dimensions: nState)
        self.mlp1 = Linear(nState, nState * 4)
        self.mlp2 = Linear(nState * 4, nState)
        self.mlpLn = LayerNorm(dimensions: nState)
        super.init()
    }

    override func items() -> ModuleItems {
        NestedDictionary(values: [
            "attn": .value(.module(attn)),
            "attn_ln": .value(.module(attnLn)),
            "cross_attn": .value(.module(crossAttn)),
            "cross_attn_ln": .value(.module(crossAttnLn)),
            "mlp1": .value(.module(mlp1)),
            "mlp2": .value(.module(mlp2)),
            "mlp_ln": .value(.module(mlpLn))
        ])
    }

    func callAsFunction(
        _ x: MLXArray,
        xa: MLXArray,
        mask: MLXArray?,
        cache: WhisperBlockCache?
    ) -> (MLXArray, WhisperBlockCache) {
        var x = x
        let selfCache = cache?.selfKV
        let (selfAttn, newSelfCache) = attn(attnLn(x), mask: mask, kvCache: selfCache)
        x = x + selfAttn

        let crossCache = cache?.crossKV
        let (crossAttnOut, newCrossCache) = crossAttn(crossAttnLn(x), xa: xa, mask: nil, kvCache: crossCache)
        x = x + crossAttnOut

        x = x + mlp2(gelu(mlp1(mlpLn(x))))
        return (x, WhisperBlockCache(selfKV: newSelfCache, crossKV: newCrossCache))
    }
}

#endif

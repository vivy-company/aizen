import Foundation
#if arch(arm64)
import MLX
import MLXNN

nonisolated final class WhisperTextDecoder: Module {
    let tokenEmbedding: Embedding
    let positionalEmbedding: MLXArray
    let blocks: [WhisperDecoderBlock]
    let ln: LayerNorm
    let mask: MLXArray

    init(dims: WhisperModelDimensions, dtype: DType) {
        self.tokenEmbedding = Embedding(embeddingCount: dims.n_vocab, dimensions: dims.n_text_state)
        self.positionalEmbedding = MLXArray.zeros([dims.n_text_ctx, dims.n_text_state], dtype: dtype)
        self.blocks = (0 ..< dims.n_text_layer).map { _ in
            WhisperDecoderBlock(nState: dims.n_text_state, nHead: dims.n_text_head)
        }
        self.ln = LayerNorm(dimensions: dims.n_text_state)
        self.mask = MLXNN.MultiHeadAttention.createAdditiveCausalMask(dims.n_text_ctx, dtype: dtype)
        super.init()
    }

    override func items() -> ModuleItems {
        let blockItems = blocks.map { NestedItem<String, ModuleValue>.value(.module($0)) }
        return NestedDictionary(values: [
            "token_embedding": .value(.module(tokenEmbedding)),
            "positional_embedding": .value(.parameters(positionalEmbedding)),
            "blocks": .array(blockItems),
            "ln": .value(.module(ln))
        ])
    }

    func callAsFunction(
        _ tokens: MLXArray,
        audioFeatures: MLXArray,
        kvCache: [WhisperBlockCache]?
    ) -> (MLXArray, [WhisperBlockCache]) {
        let offset: Int
        if let cache = kvCache, let first = cache.first, let key = first.selfKV?.key {
            offset = key.dim(1)
        } else {
            offset = 0
        }

        let length = tokens.dim(1)
        let posSlice = positionalEmbedding[offset ..< (offset + length), .ellipsis]
        var x = tokenEmbedding(tokens) + posSlice

        let cache = kvCache ?? Array(repeating: WhisperBlockCache(), count: blocks.count)
        var newCache: [WhisperBlockCache] = []
        newCache.reserveCapacity(blocks.count)

        for (index, block) in blocks.enumerated() {
            let (y, updated) = block(x, xa: audioFeatures, mask: mask, cache: cache[index])
            x = y
            newCache.append(updated)
        }

        x = ln(x)
        let logits = tokenEmbedding.asLinear(x)
        return (logits, newCache)
    }
}

#endif

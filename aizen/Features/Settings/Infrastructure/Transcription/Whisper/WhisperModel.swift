import Foundation
#if arch(arm64)
import MLX
import MLXNN

nonisolated struct WhisperModelDimensions: Codable {
    let n_mels: Int
    let n_audio_ctx: Int
    let n_audio_state: Int
    let n_audio_head: Int
    let n_audio_layer: Int
    let n_vocab: Int
    let n_text_ctx: Int
    let n_text_state: Int
    let n_text_head: Int
    let n_text_layer: Int
}

nonisolated struct WhisperKVCache {
    let key: MLXArray
    let value: MLXArray
}

nonisolated struct WhisperBlockCache {
    var selfKV: WhisperKVCache?
    var crossKV: WhisperKVCache?
}

nonisolated final class WhisperEncoderBlock: Module {
    let attn: WhisperMultiHeadAttention
    let attnLn: LayerNorm
    let mlp1: Linear
    let mlp2: Linear
    let mlpLn: LayerNorm

    init(nState: Int, nHead: Int) {
        self.attn = WhisperMultiHeadAttention(nState: nState, nHead: nHead)
        self.attnLn = LayerNorm(dimensions: nState)
        self.mlp1 = Linear(nState, nState * 4)
        self.mlp2 = Linear(nState * 4, nState)
        self.mlpLn = LayerNorm(dimensions: nState)
        super.init()
    }

    override func items() -> ModuleItems {
        NestedDictionary(values: [
            "attn": .value(.module(attn)),
            "attn_ln": .value(.module(attnLn)),
            "mlp1": .value(.module(mlp1)),
            "mlp2": .value(.module(mlp2)),
            "mlp_ln": .value(.module(mlpLn))
        ])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = x
        let (y, _) = attn(attnLn(x), mask: nil, kvCache: nil)
        x = x + y
        x = x + mlp2(gelu(mlp1(mlpLn(x))))
        return x
    }
}

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

nonisolated final class WhisperModel: Module {
    let dims: WhisperModelDimensions
    let encoder: WhisperAudioEncoder
    let decoder: WhisperTextDecoder

    init(dims: WhisperModelDimensions, dtype: DType) {
        self.dims = dims
        self.encoder = WhisperAudioEncoder(dims: dims)
        self.decoder = WhisperTextDecoder(dims: dims, dtype: dtype)
        super.init()
    }

    override func items() -> ModuleItems {
        NestedDictionary(values: [
            "encoder": .value(.module(encoder)),
            "decoder": .value(.module(decoder))
        ])
    }

    static func sinusoids(length: Int, channels: Int, maxTimescale: Double = 10_000) -> MLXArray {
        precondition(channels % 2 == 0)
        let half = channels / 2
        let logIncrement = log(maxTimescale) / Double(half - 1)
        let invTimescales = exp(-MLXArray.arange(half, dtype: .float32) * Float(logIncrement))
        let scaledTime = MLXArray.arange(length, dtype: .float32).reshaped(length, 1) * invTimescales.reshaped(1, half)
        let sin = sin(scaledTime)
        let cos = cos(scaledTime)
        return concatenated([sin, cos], axis: 1)
    }

    var isMultilingual: Bool { dims.n_vocab >= 51865 }
}
#endif

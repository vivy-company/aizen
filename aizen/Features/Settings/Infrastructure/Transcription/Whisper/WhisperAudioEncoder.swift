import Foundation
#if arch(arm64)
import MLX
import MLXNN

nonisolated final class WhisperAudioEncoder: Module {
    let conv1: Conv1d
    let conv2: Conv1d
    let positionalEmbedding: MLXArray
    let blocks: [WhisperEncoderBlock]
    let lnPost: LayerNorm

    init(dims: WhisperModelDimensions) {
        self.conv1 = Conv1d(inputChannels: dims.n_mels, outputChannels: dims.n_audio_state, kernelSize: 3, padding: 1)
        self.conv2 = Conv1d(inputChannels: dims.n_audio_state, outputChannels: dims.n_audio_state, kernelSize: 3, stride: 2, padding: 1)
        self.positionalEmbedding = WhisperModel.sinusoids(length: dims.n_audio_ctx, channels: dims.n_audio_state)
            .asType(.float16)
        self.blocks = (0 ..< dims.n_audio_layer).map { _ in
            WhisperEncoderBlock(nState: dims.n_audio_state, nHead: dims.n_audio_head)
        }
        self.lnPost = LayerNorm(dimensions: dims.n_audio_state)
        super.init()
    }

    override func items() -> ModuleItems {
        let blockItems = blocks.map { NestedItem<String, ModuleValue>.value(.module($0)) }
        return NestedDictionary(values: [
            "conv1": .value(.module(conv1)),
            "conv2": .value(.module(conv2)),
            "blocks": .array(blockItems),
            "ln_post": .value(.module(lnPost))
        ])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var x = gelu(conv1(x))
        x = gelu(conv2(x))
        x = x + positionalEmbedding

        for block in blocks {
            x = block(x)
        }

        return lnPost(x)
    }
}

#endif

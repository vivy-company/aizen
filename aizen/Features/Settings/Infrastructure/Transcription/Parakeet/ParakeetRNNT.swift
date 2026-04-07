import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Prediction Network

@preconcurrency nonisolated public class PredictNetwork: Module {
    let config: PredictConfig
    let predHidden: Int
    let embed: Embedding
    let decRNN: CustomLSTM

    public init(config: PredictConfig) {
        self.config = config
        self.predHidden = config.prednet.predHidden

        let vocabSize = config.blankAsPad ? config.vocabSize + 1 : config.vocabSize
        self.embed = Embedding(
            embeddingCount: vocabSize,
            dimensions: config.prednet.predHidden
        )

        let hiddenSize = config.prednet.rnnHiddenSize ?? config.prednet.predHidden
        let numLayers = config.prednet.predRNNLayers

        // Always use CustomLSTM to match Python implementation
        self.decRNN = CustomLSTM(
            inputSize: config.prednet.predHidden,
            hiddenSize: hiddenSize,
            numLayers: numLayers,
            bias: true,
            batchFirst: true
        )

        super.init()
    }

    public func callAsFunction(
        _ input: MLXArray?,
        _ hiddenState: (MLXArray, MLXArray)?
    ) -> (MLXArray, (MLXArray, MLXArray)) {

        let embeddedInput: MLXArray
        if let input = input {
            embeddedInput = embed(input)
        } else {
            // When no input, determine batch size from hidden state
            // Python: batch = 1 if h_c is None else h_c[0].shape[1]
            let batchSize: Int
            if let hiddenState = hiddenState {
                // Python: h_c[0].shape[1] - hidden state is [num_layers, batch, hidden]
                batchSize = hiddenState.0.shape[1]
            } else {
                batchSize = 1
            }
            // Python: mx.zeros((batch, 1, self.pred_hidden))
            embeddedInput = MLXArray.zeros([batchSize, 1, predHidden])
        }

        // Use CustomLSTM consistently
        let (outputs, finalState) = decRNN(embeddedInput, hiddenState: hiddenState)

        return (outputs, finalState)
    }
}

// MARK: - Activation Modules

@preconcurrency nonisolated public class ReLU: Module {
    public override init() {
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return MLX.maximum(x, MLXArray(0.0))
    }
}

@preconcurrency nonisolated public class Sigmoid: Module {
    public override init() {
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return MLX.sigmoid(x)
    }
}

@preconcurrency nonisolated public class Tanh: Module {
    public override init() {
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return MLX.tanh(x)
    }
}

// MARK: - Helper RNN Implementations (if needed for GRU)

@preconcurrency nonisolated public class GRU: Module {
    let inputSize: Int
    let hiddenSize: Int
    let Wih: Linear  // input to hidden
    let Whh: Linear  // hidden to hidden

    public init(inputSize: Int, hiddenSize: Int) {
        self.inputSize = inputSize
        self.hiddenSize = hiddenSize

        // GRU has 3 gates: reset, update, new
        self.Wih = Linear(inputSize, 3 * hiddenSize, bias: true)
        self.Whh = Linear(hiddenSize, 3 * hiddenSize, bias: false)

        super.init()
    }

    public func callAsFunction(
        _ input: MLXArray,
        hidden: MLXArray? = nil
    ) -> (MLXArray, MLXArray) {

        let batchSize = input.shape[0]
        let seqLen = input.shape[1]

        let h0 = hidden ?? MLXArray.zeros([batchSize, hiddenSize])

        var outputs: [MLXArray] = []
        var ht = h0

        for t in 0..<seqLen {
            let xt = input[0..., t]

            // Compute reset and update gates
            let ihGates = Wih(xt)
            let hhGates = Whh(ht)

            let ihChunks = ihGates.split(parts: 3, axis: 1)
            let hhChunks = hhGates.split(parts: 3, axis: 1)

            let resetGate = sigmoid(ihChunks[0] + hhChunks[0])
            let updateGate = sigmoid(ihChunks[1] + hhChunks[1])
            let newGate = tanh(ihChunks[2] + resetGate * hhChunks[2])

            // Update hidden state
            ht = (1.0 - updateGate) * newGate + updateGate * ht

            outputs.append(ht.expandedDimensions(axis: 1))
        }

        let output = MLX.concatenated(outputs, axis: 1)
        return (output, ht)
    }
}
#endif

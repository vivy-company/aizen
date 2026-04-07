import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

@preconcurrency nonisolated public class CustomLSTM: Module {
    let inputSize: Int
    let hiddenSize: Int
    let numLayers: Int
    let batchFirst: Bool
    let lstmLayers: [MLXNN.LSTM]

    public init(
        inputSize: Int,
        hiddenSize: Int,
        numLayers: Int = 1,
        bias: Bool = true,
        batchFirst: Bool = true
    ) {
        self.inputSize = inputSize
        self.hiddenSize = hiddenSize
        self.numLayers = numLayers
        self.batchFirst = batchFirst

        var layers: [MLXNN.LSTM] = []
        for i in 0..<numLayers {
            let layerInputSize = (i == 0) ? inputSize : hiddenSize
            layers.append(
                MLXNN.LSTM(
                    inputSize: layerInputSize,
                    hiddenSize: hiddenSize,
                    bias: bias
                ))
        }
        self.lstmLayers = layers

        super.init()
    }

    public func callAsFunction(
        _ input: MLXArray,
        hiddenState: (MLXArray, MLXArray)?
    ) -> (MLXArray, (MLXArray, MLXArray)) {

        var x = input

        if batchFirst {
            x = x.transposed(axes: [1, 0, 2])
        }

        let h: [MLXArray?]
        let c: [MLXArray?]

        if let hiddenState {
            h = (0..<numLayers).map { i in hiddenState.0[i] }
            c = (0..<numLayers).map { i in hiddenState.1[i] }
        } else {
            h = Array(repeating: nil, count: numLayers)
            c = Array(repeating: nil, count: numLayers)
        }

        var outputs = x
        var nextH: [MLXArray] = []
        var nextC: [MLXArray] = []

        for i in 0..<numLayers {
            let layer = lstmLayers[i]
            let (allHidden, allCell) = layer(outputs, hidden: h[i], cell: c[i])
            outputs = allHidden

            let finalHidden = allHidden[-1]
            let finalCell = allCell[-1]

            nextH.append(finalHidden)
            nextC.append(finalCell)
        }

        if batchFirst {
            outputs = outputs.transposed(axes: [1, 0, 2])
        }

        let finalH = MLX.stacked(nextH, axis: 0)
        let finalC = MLX.stacked(nextC, axis: 0)

        return (outputs, (finalH, finalC))
    }
}

#endif

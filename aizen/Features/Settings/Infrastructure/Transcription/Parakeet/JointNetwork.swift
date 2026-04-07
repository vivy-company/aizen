import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

@preconcurrency nonisolated public class JointNetwork: Module {
    let config: JointConfig
    let numClasses: Int
    let encLinear: Linear
    let predLinear: Linear
    let activation: Module
    let jointLinear: Linear

    public init(config: JointConfig) {
        self.config = config
        self.numClasses = config.numClasses + 1 + config.numExtraOutputs

        self.encLinear = Linear(config.jointnet.encoderHidden, config.jointnet.jointHidden)
        self.predLinear = Linear(config.jointnet.predHidden, config.jointnet.jointHidden)

        switch config.jointnet.activation.lowercased() {
        case "relu":
            self.activation = ReLU()
        case "sigmoid":
            self.activation = Sigmoid()
        case "tanh":
            self.activation = Tanh()
        default:
            fatalError("Unsupported activation for joint step - please pass one of [relu, sigmoid, tanh]")
        }

        self.jointLinear = Linear(config.jointnet.jointHidden, numClasses)

        super.init()
    }

    public func callAsFunction(
        _ encoderOutput: MLXArray,
        _ predictionOutput: MLXArray
    ) -> MLXArray {
        let encProj = encLinear(encoderOutput)
        let predProj = predLinear(predictionOutput)

        let encExpanded = encProj.expandedDimensions(axis: 2)
        let predExpanded = predProj.expandedDimensions(axis: 1)
        var x = encExpanded + predExpanded

        if let relu = activation as? ReLU {
            x = relu.callAsFunction(x)
        } else if let sigmoid = activation as? Sigmoid {
            x = sigmoid.callAsFunction(x)
        } else if let tanh = activation as? Tanh {
            x = tanh.callAsFunction(x)
        }

        x = jointLinear(x)
        return x
    }
}

#endif

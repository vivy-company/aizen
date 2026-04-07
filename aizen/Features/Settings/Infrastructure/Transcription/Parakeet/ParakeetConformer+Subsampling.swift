import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Depth-wise Striding Subsampling

@preconcurrency nonisolated public class DwStridingSubsampling: Module {
    let subsamplingConvChunkingFactor: Int
    let convChannels: Int
    let samplingNum: Int
    let stride: Int
    let kernelSize: Int
    let padding: Int
    let conv: [Module]
    let out: Linear
    let finalFreqDim: Int

    public init(config: ConformerConfig) {
        assert(
            config.subsamplingFactor > 0
                && (config.subsamplingFactor & (config.subsamplingFactor - 1)) == 0)

        self.subsamplingConvChunkingFactor = config.subsamplingConvChunkingFactor
        self.convChannels = config.subsamplingConvChannels
        self.samplingNum = Int(log2(Double(config.subsamplingFactor)))
        self.stride = 2
        self.kernelSize = 3
        self.padding = (self.kernelSize - 1) / 2

        var inChannels = 1
        var finalFreqDim = config.featIn

        for _ in 0..<samplingNum {
            finalFreqDim =
                Int(floor(Double(finalFreqDim + 2 * padding - kernelSize) / Double(stride))) + 1
            if finalFreqDim < 1 {
                fatalError("Non-positive final frequency dimension!")
            }
        }

        var convLayers: [Module] = []
        convLayers.append(
            Conv2d(
                inputChannels: inChannels,
                outputChannels: convChannels,
                kernelSize: IntOrPair((kernelSize, kernelSize)),
                stride: IntOrPair((stride, stride)),
                padding: IntOrPair((padding, padding))
            )
        )
        convLayers.append(ReLU())

        inChannels = convChannels

        for _ in 0..<(samplingNum - 1) {
            convLayers.append(
                Conv2d(
                    inputChannels: inChannels,
                    outputChannels: inChannels,
                    kernelSize: IntOrPair((kernelSize, kernelSize)),
                    stride: IntOrPair((stride, stride)),
                    padding: IntOrPair((padding, padding)),
                    groups: inChannels
                )
            )

            convLayers.append(
                Conv2d(
                    inputChannels: inChannels,
                    outputChannels: convChannels,
                    kernelSize: IntOrPair((1, 1)),
                    stride: IntOrPair((1, 1)),
                    padding: IntOrPair((0, 0))
                )
            )

            convLayers.append(ReLU())
        }

        self.conv = convLayers
        self.out = Linear(convChannels * finalFreqDim, config.dModel)
        self.finalFreqDim = finalFreqDim

        super.init()
    }

    private func convForward(_ x: MLXArray) -> MLXArray {
        var x = x.transposed(axes: [0, 2, 3, 1])

        for (i, layer) in conv.enumerated() {
            if let convLayer = layer as? Conv2d {
                x = convLayer(x)
            } else if let reluLayer = layer as? ReLU {
                x = reluLayer(x)
            }

            let afterMax = x.max().item(Float.self)
            if afterMax.isInfinite || afterMax.isNaN {
                fatalError("DwStridingSubsampling layer \(i) produced -inf values")
            }
        }

        x = x.transposed(axes: [0, 3, 1, 2])
        return x
    }

    public func callAsFunction(_ x: MLXArray, lengths: MLXArray) -> (MLXArray, MLXArray) {
        var lengths = lengths

        for _ in 0..<samplingNum {
            lengths = floor((lengths + Float(2 * padding - kernelSize)) / Float(stride)) + 1.0
        }
        lengths = lengths.asType(.int32)

        var x = x.expandedDimensions(axis: 1)
        x = convForward(x)

        x = x.swappedAxes(1, 2)
        let batchSize = x.shape[0]
        let timeSteps = x.shape[1]
        let featuresFlattened = x.shape[2] * x.shape[3]

        x = x.reshaped([batchSize, timeSteps, featuresFlattened])
        x = out(x)

        return (x, lengths)
    }
}
#endif

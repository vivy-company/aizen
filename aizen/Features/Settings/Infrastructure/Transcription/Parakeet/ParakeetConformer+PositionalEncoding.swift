import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

// MARK: - Positional Encoding

@preconcurrency nonisolated public class RelPositionalEncoding: Module {
    let dModel: Int
    var maxLen: Int
    let scaleInput: Bool
    var posEmb: MLXArray

    public init(dModel: Int, maxLen: Int, scaleInput: Bool = false) {
        assert(dModel % 2 == 0 && maxLen > 0, "dModel must be even and maxLen must be positive")

        self.dModel = dModel
        self.maxLen = maxLen
        self.scaleInput = scaleInput
        self.posEmb = MLXArray.zeros([2 * maxLen - 1, dModel])

        super.init()
        calculatePE()
    }

    internal func calculatePE() {
        let positions = MLXArray(
            stride(from: maxLen - 1, through: -(maxLen - 1), by: -1).map(Float.init)
        )
        .expandedDimensions(axis: 1)

        let divTerm = positionalExp(
            MLXArray(stride(from: 0, to: dModel, by: 2).map(Float.init))
                * (-positionalLog(10000.0) / Float(dModel))
        )

        let pe = MLXArray.zeros([2 * maxLen - 1, dModel])
        let sinValues = positionalSin(positionalMatmul(positions, divTerm.expandedDimensions(axis: 0)))
        let cosValues = positionalCos(positionalMatmul(positions, divTerm.expandedDimensions(axis: 0)))

        for i in 0..<(dModel / 2) {
            pe[0..., 2 * i] = sinValues[0..., i]
            pe[0..., 2 * i + 1] = cosValues[0..., i]
        }

        self.posEmb = pe.expandedDimensions(axis: 0)
        MLX.eval(self.posEmb)
    }

    public func callAsFunction(_ x: MLXArray, offset: Int = 0) -> (MLXArray, MLXArray) {
        var x = x
        let inputLen = x.shape[1] + offset

        if scaleInput {
            x = x * positionalSqrt(Float(dModel))
        }

        if inputLen > maxLen {
            maxLen = inputLen + 1
            calculatePE()
        }

        let bufferLen = posEmb.shape[1]
        let startIdx = max(0, bufferLen / 2 - (inputLen - 1))
        let endIdx = min(bufferLen, bufferLen / 2 + (inputLen - 1) + 1)

        guard startIdx < bufferLen && endIdx <= bufferLen && startIdx < endIdx else {
            fatalError(
                "Positional encoding index out of bounds: startIdx=\(startIdx), endIdx=\(endIdx), bufferLen=\(bufferLen), inputLen=\(inputLen)"
            )
        }

        let posEmbSlice = posEmb[0..., startIdx..<endIdx].asType(x.dtype)
        return (x, posEmbSlice)
    }
}

@preconcurrency nonisolated public class LocalRelPositionalEncoding: RelPositionalEncoding {
    let leftContext: Int
    let rightContext: Int

    public init(
        dModel: Int, maxLen: Int, scaleInput: Bool = false, contextSize: (Int, Int) = (256, 256)
    ) {
        self.leftContext = contextSize.0
        self.rightContext = contextSize.1
        super.init(dModel: dModel, maxLen: maxLen, scaleInput: scaleInput)
    }

    override func calculatePE() {
        let positions = MLXArray(
            stride(from: leftContext, through: -rightContext, by: -1).map(Float.init)
        )
        .expandedDimensions(axis: 1)

        let divTerm = positionalExp(
            MLXArray(stride(from: 0, to: dModel, by: 2).map(Float.init))
                * (-positionalLog(10000.0) / Float(dModel))
        )

        let pe = MLXArray.zeros([leftContext + rightContext + 1, dModel])
        let sinValues = positionalSin(positionalMatmul(positions, divTerm.expandedDimensions(axis: 0)))
        let cosValues = positionalCos(positionalMatmul(positions, divTerm.expandedDimensions(axis: 0)))

        for i in 0..<(dModel / 2) {
            pe[0..., 2 * i] = sinValues[0..., i]
            pe[0..., 2 * i + 1] = cosValues[0..., i]
        }

        self.posEmb = pe.expandedDimensions(axis: 0)
        MLX.eval(self.posEmb)
    }

    public override func callAsFunction(_ x: MLXArray, offset: Int = 0) -> (MLXArray, MLXArray) {
        var x = x
        if scaleInput {
            x = x * positionalSqrt(Float(dModel))
        }

        let endIdx = leftContext + rightContext + 1
        let posEmbSlice = posEmb[0..., 0..<endIdx].asType(x.dtype)
        return (x, posEmbSlice)
    }
}

// MARK: - Utility Functions

nonisolated private func positionalFloor(_ x: MLXArray) -> MLXArray {
    MLX.floor(x)
}

nonisolated private func positionalSin(_ x: MLXArray) -> MLXArray {
    MLX.sin(x)
}

nonisolated private func positionalCos(_ x: MLXArray) -> MLXArray {
    MLX.cos(x)
}

nonisolated private func positionalExp(_ x: MLXArray) -> MLXArray {
    MLX.exp(x)
}

nonisolated private func positionalLog(_ x: Float) -> Float {
    Foundation.log(x)
}

nonisolated private func positionalSqrt(_ x: Float) -> Float {
    Foundation.sqrt(x)
}

nonisolated private func positionalMatmul(_ a: MLXArray, _ b: MLXArray) -> MLXArray {
    MLX.matmul(a, b)
}
#endif

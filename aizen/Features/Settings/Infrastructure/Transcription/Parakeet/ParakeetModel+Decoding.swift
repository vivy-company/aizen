import Foundation
#if arch(arm64)
import MLX

extension ParakeetTDT {
    nonisolated public func generate(mel: MLXArray) throws -> [AlignedResult] {
        let inputMel = mel.ndim == 2 ? mel.expandedDimensions(axis: 0) : mel

        let (features, lengths) = encoder(inputMel)
        let (results, _) = try decode(features: features, lengths: lengths, config: DecodingConfig())

        return results.map { tokens in
            sentencesToResult(tokensToSentences(tokens))
        }
    }

    nonisolated public func decode(
        features: MLXArray,
        lengths: MLXArray? = nil,
        lastToken: [Int?]? = nil,
        hiddenState: [(MLXArray, MLXArray)?]? = nil,
        config: DecodingConfig = DecodingConfig()
    ) throws -> ([[AlignedToken]], [(MLXArray, MLXArray)?]) {

        guard config.decoding == "greedy" else {
            throw ParakeetError.unsupportedDecoding("Only greedy decoding is supported for TDT decoder")
        }

        let (batchCount, sequenceLength) = (features.shape[0], features.shape[1])
        let actualLengths = lengths ?? MLXArray(Array(repeating: sequenceLength, count: batchCount))
        let actualLastToken = lastToken ?? Array(repeating: nil, count: batchCount)
        var actualHiddenState = hiddenState ?? Array(repeating: nil, count: batchCount)

        var results: [[AlignedToken]] = []

        for batch in 0..<batchCount {
            var hypothesis: [AlignedToken] = []
            let feature = features[batch].expandedDimensions(axis: 0)
            let length = Int(actualLengths[batch].item(Int32.self))

            var step = 0
            var newSymbols = 0
            var currentLastToken = actualLastToken[batch]

            while step < length {
                let decoderInput = currentLastToken.map { token in
                    MLXArray([token]).expandedDimensions(axis: 0)
                }

                let (decoderOut, newHidden) = decoder(decoderInput, actualHiddenState[batch])
                let decoderOutput = decoderOut.asType(feature.dtype)
                let decoderHidden = (
                    newHidden.0.asType(feature.dtype), newHidden.1.asType(feature.dtype)
                )

                let jointOut = joint(feature[0..., step..<(step + 1)], decoderOutput)
                MLX.eval(jointOut)

                let jointOutNaNCheck = jointOut.max().item(Float.self)
                if jointOutNaNCheck.isNaN {
                    break
                }

                let vocabSize = vocabulary.count

                guard jointOut.shape.count >= 4 else {
                    throw ParakeetError.audioProcessingError(
                        "Joint output has insufficient dimensions: \(jointOut.shape)")
                }

                let lastDim = jointOut.shape[jointOut.shape.count - 1]
                guard lastDim > vocabSize else {
                    throw ParakeetError.audioProcessingError(
                        "Joint output last dimension (\(lastDim)) is not larger than vocab size (\(vocabSize))"
                    )
                }

                let vocabSlice = jointOut[0, 0, 0..., 0..<(vocabSize + 1)]
                let decisionSlice = jointOut[0, 0, 0..., (vocabSize + 1)..<lastDim]

                guard vocabSlice.shape[0] > 0 && decisionSlice.shape[0] > 0 else {
                    throw ParakeetError.audioProcessingError(
                        "Empty slices: vocab=\(vocabSlice.shape), decision=\(decisionSlice.shape)")
                }

                let predToken = Int(vocabSlice.argMax(axis: -1).item(Int32.self))
                let decision = Int(decisionSlice.argMax(axis: -1).item(Int32.self))

                if predToken != vocabSize {
                    let tokenText = ParakeetTokenizer.decode([predToken], vocabulary)
                    let startTime =
                        Float(step * encoderConfig.subsamplingFactor)
                        / Float(preprocessConfig.sampleRate) * Float(preprocessConfig.hopLength)
                    let duration =
                        Float(durations[decision] * encoderConfig.subsamplingFactor)
                        / Float(preprocessConfig.sampleRate) * Float(preprocessConfig.hopLength)

                    hypothesis.append(
                        AlignedToken(
                            id: predToken,
                            start: startTime,
                            duration: duration,
                            text: tokenText
                        ))

                    currentLastToken = predToken
                    actualHiddenState[batch] = decoderHidden
                }

                step += durations[decision]
                newSymbols += 1

                if durations[decision] != 0 {
                    newSymbols = 0
                } else if newSymbols >= maxSymbols {
                    step += 1
                    newSymbols = 0
                }

                if newSymbols > 100 {
                    break
                }
            }

            results.append(hypothesis)
        }

        return (results, actualHiddenState)
    }
}

#endif

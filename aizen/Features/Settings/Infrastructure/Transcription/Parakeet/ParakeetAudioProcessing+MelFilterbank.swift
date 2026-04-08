import Accelerate
import Foundation
#if arch(arm64)
import MLX

// MARK: - Mel Filterbank

nonisolated func createMelFilterbank(
    sampleRate: Int,
    nFFT: Int,
    nMels: Int
) throws -> MLXArray {

    let nyquist = Float(sampleRate) / 2.0
    let nFreqs = nFFT / 2 + 1

    // Create mel scale points
    let melMin = hzToMel(0.0)
    let melMax = hzToMel(nyquist)
    let melPoints = MLXArray.linspace(melMin, melMax, count: nMels + 2)

    // Convert back to Hz
    let hzPoints = melToHz(melPoints)

    // Convert to FFT bin indices
    let binIndices = hzPoints * Float(nFFT) / Float(sampleRate)

    // Create filterbank
    let filterbank = MLXArray.zeros([nMels, nFreqs])

    for m in 0..<nMels {
        let leftBin = binIndices[m].item(Float.self)
        let centerBin = binIndices[m + 1].item(Float.self)
        let rightBin = binIndices[m + 2].item(Float.self)

        // Create triangular filter with continuous values (not just integer bins)
        for f in 0..<nFreqs {
            let freq = Float(f)

            if freq >= leftBin && freq <= centerBin && centerBin > leftBin {
                let weight = (freq - leftBin) / (centerBin - leftBin)
                filterbank[m, f] = MLXArray(weight)
            } else if freq > centerBin && freq <= rightBin && rightBin > centerBin {
                let weight = (rightBin - freq) / (rightBin - centerBin)
                filterbank[m, f] = MLXArray(weight)
            }
        }

        // Apply exact "slaney" normalization to match librosa
        // Slaney normalization: 2.0 / (mel_f[i+2] - mel_f[i])
        let melRange = melPoints[m + 2].item(Float.self) - melPoints[m].item(Float.self)
        if melRange > 0 {
            let slaneynorm = 2.0 / melRange
            filterbank[m] = filterbank[m] * slaneynorm
        }
    }

    return filterbank
}

// MARK: - Mel Scale Conversion

nonisolated private func hzToMel(_ hz: Float) -> Float {
    return 2595.0 * log10(1.0 + hz / 700.0)
}

nonisolated private func hzToMel(_ hz: MLXArray) -> MLXArray {
    return 2595.0 * log10(1.0 + hz / 700.0)
}

nonisolated private func melToHz(_ mel: MLXArray) -> MLXArray {
    return 700.0 * (pow(10.0, mel / 2595.0) - 1.0)
}
#endif

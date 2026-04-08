import Accelerate
import Foundation
#if arch(arm64)
import MLX

// MARK: - Audio Processing Functions

/// Compute log mel spectrogram from audio data
nonisolated public func getLogMel(_ audio: MLXArray, config: PreprocessConfig) throws -> MLXArray {
    let originalDType = audio.dtype
    var x = audio

    // Pad audio if needed
    if config.padTo > 0 && x.shape.last! < config.padTo {
        let padLength = config.padTo - x.shape.last!
        let padArray = Array(repeating: (0, 0), count: x.ndim)
        var padArray2 = padArray
        padArray2[padArray2.count - 1] = (0, padLength)
        x = MLX.padded(
            x, widths: padArray2.map { IntOrPair($0) }, mode: .constant,
            value: MLXArray(config.padValue))
    }

    // Apply pre-emphasis if configured
    if let preemph = config.preemph {
        let prefix = x[0..<1]
        let diff = x[1...] - preemph * x[0..<(x.shape[0] - 1)]
        x = MLX.concatenated([prefix, diff], axis: 0)
    }

    // Get window function
    let window = try getWindow(config.window, length: config.winLength, dtype: x.dtype)

    // Compute STFT
    x = try stft(
        x,
        nFFT: config.nFFT,
        hopLength: config.hopLength,
        winLength: config.winLength,
        window: window
    )

    // Compute magnitude spectrum
    let magnitude = abs(x)
    var powerSpectrum = magnitude

    if config.magPower != 1.0 {
        powerSpectrum = pow(magnitude, config.magPower)
    }

    // Apply mel filterbank
    let melFilters = try createMelFilterbank(
        sampleRate: config.sampleRate,
        nFFT: config.nFFT,
        nMels: config.features
    )

    let melSpectrum = matmul(
        melFilters.asType(powerSpectrum.dtype), powerSpectrum.transposed(axes: [1, 0]))
    let logMelSpectrum = log(melSpectrum + 1e-5)

    // Normalize
    let normalizedMel: MLXArray
    if config.normalize == "per_feature" {
        let mean = logMelSpectrum.mean(axes: [1], keepDims: true)
        let std = logMelSpectrum.std(axes: [1], keepDims: true)
        normalizedMel = (logMelSpectrum - mean) / (std + 1e-5)
    } else {
        let mean = logMelSpectrum.mean()
        let std = logMelSpectrum.std()
        normalizedMel = (logMelSpectrum - mean) / (std + 1e-5)
    }

    // Transpose and add batch dimension
    let output = normalizedMel.transposed(axes: [1, 0]).expandedDimensions(axis: 0)

    return output.asType(originalDType)
}

#endif

import Accelerate
import Foundation
#if arch(arm64)
import MLX

// MARK: - STFT Implementation

nonisolated func stft(
    _ x: MLXArray,
    nFFT: Int,
    hopLength: Int,
    winLength: Int,
    window: MLXArray
) throws -> MLXArray {

    // Pad the window to nFFT length if needed
    var actualWindow = window
    if winLength != nFFT {
        if winLength > nFFT {
            actualWindow = window[0..<nFFT]
        } else {
            let padding = nFFT - winLength
            let padArray = [(0, padding)]
            actualWindow = MLX.padded(
                window, widths: padArray.map { IntOrPair($0) }, mode: .constant,
                value: MLXArray(0.0))
        }
    }

    // Pad the signal
    let padding = nFFT / 2
    var paddedX = x

    // Reflect padding (simplified)
    let prefix = x[1..<(padding + 1)].reversed(axes: [0])
    let suffix = x[(x.shape[0] - padding - 1)..<(x.shape[0] - 1)].reversed(axes: [0])
    paddedX = MLX.concatenated([prefix, x, suffix], axis: 0)

    // Create frames
    let numFrames = (paddedX.shape[0] - nFFT + hopLength) / hopLength
    var frames: [MLXArray] = []

    for i in 0..<numFrames {
        let start = i * hopLength
        let end = start + nFFT
        if end <= paddedX.shape[0] {
            let frame = paddedX[start..<end] * actualWindow
            frames.append(frame)
        }
    }

    if frames.isEmpty {
        throw ParakeetError.audioProcessingError("No frames could be extracted")
    }

    let frameMatrix = MLX.stacked(frames, axis: 0)

    // Apply FFT
    let fftResult = MLX.rfft(frameMatrix, axis: -1)

    return fftResult
}
#endif

import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

extension RelPositionMultiHeadLocalAttention {
    nonisolated func matmulQK(_ q: MLXArray, _ k: MLXArray, w: Int) -> MLXArray {
        let kernelSource = """
            uint B = q_shape[0];
            uint H = q_shape[1];
            uint S_q = q_shape[2];
            uint S_k = k_shape[2];
            uint K_rel = 2 * W + 1;

            uint target_idx = thread_position_in_grid.x;
            uint k_rel_idx = thread_position_in_grid.y;

            if (target_idx >= B * H * S_q) return;

            uint s_q_idx = target_idx % S_q;
            uint remaining_idx = target_idx / S_q;
            uint h_idx = remaining_idx % H;
            uint b_idx = remaining_idx / H;
            uint k_offset = k_rel_idx;

            uint stick_q_k_idx = S_k - S_q + s_q_idx;
            int s_k_idx_signed = int(stick_q_k_idx) + int(k_offset) - int(W);
            bool is_out_of_bounds = (s_k_idx_signed < 0) || (s_k_idx_signed >= S_k);

            T result;

            if (!is_out_of_bounds) {
                uint s_k_idx = uint(s_k_idx_signed);

                uint Q_D_stride = D;
                uint Q_S_stride = S_q * Q_D_stride;
                uint Q_H_stride = H * Q_S_stride;
                uint K_D_stride = D;
                uint K_S_stride = S_k * K_D_stride;
                uint K_H_stride = H * K_S_stride;

                uint q_base_offset = b_idx * Q_H_stride + h_idx * Q_S_stride + s_q_idx * Q_D_stride;
                uint k_base_offset = b_idx * K_H_stride + h_idx * K_S_stride + s_k_idx * K_D_stride;

                const device T* q_vec_ptr = q + q_base_offset;
                const device T* k_vec_ptr = k + k_base_offset;

                result = T(0.0);
                uint d_idx = 0;

                for (; d_idx + 16 <= D; d_idx += 16) {
                    T q_vals[16], k_vals[16];
                    for (uint i = 0; i < 16; ++i) {
                        q_vals[i] = q_vec_ptr[d_idx + i];
                        k_vals[i] = k_vec_ptr[d_idx + i];
                    }

                    result +=
                        q_vals[0] * k_vals[0] + q_vals[1] * k_vals[1] +
                        q_vals[2] * k_vals[2] + q_vals[3] * k_vals[3] +
                        q_vals[4] * k_vals[4] + q_vals[5] * k_vals[5] +
                        q_vals[6] * k_vals[6] + q_vals[7] * k_vals[7] +
                        q_vals[8] * k_vals[8] + q_vals[9] * k_vals[9] +
                        q_vals[10] * k_vals[10] + q_vals[11] * k_vals[11] +
                        q_vals[12] * k_vals[12] + q_vals[13] * k_vals[13] +
                        q_vals[14] * k_vals[14] + q_vals[15] * k_vals[15];
                }

                for (; d_idx + 8 <= D; d_idx += 8) {
                    result +=
                        q_vec_ptr[d_idx] * k_vec_ptr[d_idx] +
                        q_vec_ptr[d_idx + 1] * k_vec_ptr[d_idx + 1] +
                        q_vec_ptr[d_idx + 2] * k_vec_ptr[d_idx + 2] +
                        q_vec_ptr[d_idx + 3] * k_vec_ptr[d_idx + 3] +
                        q_vec_ptr[d_idx + 4] * k_vec_ptr[d_idx + 4] +
                        q_vec_ptr[d_idx + 5] * k_vec_ptr[d_idx + 5] +
                        q_vec_ptr[d_idx + 6] * k_vec_ptr[d_idx + 6] +
                        q_vec_ptr[d_idx + 7] * k_vec_ptr[d_idx + 7];
                }

                for (; d_idx + 4 <= D; d_idx += 4) {
                    result +=
                        q_vec_ptr[d_idx] * k_vec_ptr[d_idx] +
                        q_vec_ptr[d_idx + 1] * k_vec_ptr[d_idx + 1] +
                        q_vec_ptr[d_idx + 2] * k_vec_ptr[d_idx + 2] +
                        q_vec_ptr[d_idx + 3] * k_vec_ptr[d_idx + 3];
                }

                for (; d_idx < D; ++d_idx) {
                    result += q_vec_ptr[d_idx] * k_vec_ptr[d_idx];
                }
            } else {
                result = T(-INFINITY);
            }

            uint out_idx = target_idx * K_rel + k_rel_idx;
            out[out_idx] = result;
        """

        let b = q.shape[0]
        let h = q.shape[1]
        let sQ = q.shape[2]
        let d = q.shape[3]

        let outputShape = [b, h, sQ, 2 * w + 1]

        let gridDimX = max(1, b * h * sQ)
        let gridDimY = max(1, 2 * w + 1)
        let gridDimZ = 1

        var tgY: Int
        var tgX: Int

        if d >= 256 {
            tgY = min(gridDimY, 4)
            tgX = min(gridDimX, 256)
        } else if d >= 128 {
            tgY = min(gridDimY, 8)
            tgX = min(gridDimX, 128)
        } else if d >= 32 {
            tgY = min(gridDimY, 16)
            tgX = min(gridDimX, 64)
        } else {
            tgY = min(gridDimY, 32)
            tgX = min(gridDimX, 32)
        }

        if tgX > 32 {
            tgX = 64
        } else if tgX > 16 {
            tgX = 32
        } else if tgX > 8 {
            tgX = 16
        } else if tgX > 4 {
            tgX = 8
        } else {
            tgX = max(tgX, 1)
        }
        tgX = max(tgX, 1)
        tgY = max(tgY, 1)

        let kernelFn = MLX.MLXFast.metalKernel(
            name: "local_qk_perf",
            inputNames: ["q", "k"],
            outputNames: ["out"],
            source: kernelSource
        )

        let outputs = kernelFn(
            [q, k],
            template: [
                ("T", q.dtype),
                ("W", w),
                ("D", d),
            ],
            grid: (gridDimX, gridDimY, gridDimZ),
            threadGroup: (tgX, tgY, 1),
            outputShapes: [outputShape],
            outputDTypes: [q.dtype]
        )

        return outputs[0]
    }
}
#endif

import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

extension RelPositionMultiHeadLocalAttention {
    nonisolated func matmulPV(_ prob: MLXArray, _ v: MLXArray, w: Int) -> MLXArray {
        let kernelSource = """
            uint B = prob_shape[0];
            uint H = prob_shape[1];
            uint S_p = prob_shape[2];
            uint S_v = v_shape[2];
            uint K_rel = 2 * W + 1;

            uint d_idx = thread_position_in_grid.x;
            uint s_p_idx = thread_position_in_grid.y;
            uint bh_idx = thread_position_in_grid.z;

            if (d_idx >= D_v || s_p_idx >= S_p || bh_idx >= (B * H)) {
                return;
            }

            uint b_idx = bh_idx / H;
            uint h_idx = bh_idx % H;

            T current_sum = 0.0f;

            uint P_H_stride = S_p * K_rel;
            uint P_B_stride = H * P_H_stride;
            uint V_H_stride = S_v * D_v;
            uint V_B_stride = H * V_H_stride;
            uint O_S_stride = D_v * H;
            uint O_B_stride = S_p * O_S_stride;

            uint stick_p_v_idx = S_v - S_p + s_p_idx;

            uint k = 0;
            for (; k + 16 <= K_rel; k += 16) {
                float prob_vals[16], v_vals[16];
                int s_v_indices[16];
                bool valid[16];

                for (uint i = 0; i < 16; ++i) {
                    s_v_indices[i] = int(stick_p_v_idx) + int(k + i) - int(W);
                    valid[i] = (s_v_indices[i] >= 0 && s_v_indices[i] < S_v);
                    if (valid[i]) {
                        uint prob_idx = b_idx * P_B_stride + h_idx * P_H_stride + s_p_idx * K_rel + (k + i);
                        uint v_idx = b_idx * V_B_stride + h_idx * V_H_stride + uint(s_v_indices[i]) * D_v + d_idx;
                        prob_vals[i] = prob[prob_idx];
                        v_vals[i] = v[v_idx];
                    } else {
                        prob_vals[i] = 0.0f;
                        v_vals[i] = 0.0f;
                    }
                }

                current_sum +=
                    prob_vals[0] * v_vals[0] + prob_vals[1] * v_vals[1] +
                    prob_vals[2] * v_vals[2] + prob_vals[3] * v_vals[3] +
                    prob_vals[4] * v_vals[4] + prob_vals[5] * v_vals[5] +
                    prob_vals[6] * v_vals[6] + prob_vals[7] * v_vals[7] +
                    prob_vals[8] * v_vals[8] + prob_vals[9] * v_vals[9] +
                    prob_vals[10] * v_vals[10] + prob_vals[11] * v_vals[11] +
                    prob_vals[12] * v_vals[12] + prob_vals[13] * v_vals[13] +
                    prob_vals[14] * v_vals[14] + prob_vals[15] * v_vals[15];
            }

            for (; k + 8 <= K_rel; k += 8) {
                for (uint i = 0; i < 8; ++i) {
                    int s_v_idx_signed = int(stick_p_v_idx) + int(k + i) - int(W);
                    if (s_v_idx_signed >= 0 && s_v_idx_signed < S_v) {
                        uint s_v_idx = uint(s_v_idx_signed);
                        uint prob_idx = b_idx * P_B_stride + h_idx * P_H_stride + s_p_idx * K_rel + (k + i);
                        uint v_idx = b_idx * V_B_stride + h_idx * V_H_stride + s_v_idx * D_v + d_idx;
                        current_sum += prob[prob_idx] * v[v_idx];
                    }
                }
            }

            for (; k + 4 <= K_rel; k += 4) {
                for (uint i = 0; i < 4; ++i) {
                    int s_v_idx_signed = int(stick_p_v_idx) + int(k + i) - int(W);
                    if (s_v_idx_signed >= 0 && s_v_idx_signed < S_v) {
                        uint s_v_idx = uint(s_v_idx_signed);
                        uint prob_idx = b_idx * P_B_stride + h_idx * P_H_stride + s_p_idx * K_rel + (k + i);
                        uint v_idx = b_idx * V_B_stride + h_idx * V_H_stride + s_v_idx * D_v + d_idx;
                        current_sum += prob[prob_idx] * v[v_idx];
                    }
                }
            }

            for (; k < K_rel; ++k) {
                int s_v_idx_signed = int(stick_p_v_idx) + int(k) - int(W);
                if (s_v_idx_signed >= 0 && s_v_idx_signed < S_v) {
                    uint s_v_idx = uint(s_v_idx_signed);
                    uint prob_idx = b_idx * P_B_stride + h_idx * P_H_stride + s_p_idx * K_rel + k;
                    uint v_idx = b_idx * V_B_stride + h_idx * V_H_stride + s_v_idx * D_v + d_idx;
                    current_sum += prob[prob_idx] * v[v_idx];
                }
            }

            uint out_idx = b_idx * O_B_stride + s_p_idx * O_S_stride + h_idx * D_v + d_idx;
            context_out[out_idx] = current_sum;
            """

        let b = prob.shape[0]
        let h = prob.shape[1]
        let sP = prob.shape[2]
        let kRel = prob.shape[3]
        let dV = v.shape[3]

        let outputShape = [b, sP, h, dV]
        let gridDimX = dV
        let gridDimY = sP
        let gridDimZ = b * h

        let tgX = min(gridDimX, 32)
        let tgY = min(gridDimY, 1024 / tgX)

        let kernelFn = MLX.MLXFast.metalKernel(
            name: "local_pv_matmul",
            inputNames: ["prob", "v"],
            outputNames: ["context_out"],
            source: kernelSource
        )

        let outputs = kernelFn(
            [prob, v],
            template: [
                ("T", prob.dtype),
                ("W", w),
                ("D", kRel),
                ("D_v", dV),
            ],
            grid: (gridDimX, gridDimY, gridDimZ),
            threadGroup: (max(1, tgX), max(1, tgY), 1),
            outputShapes: [outputShape],
            outputDTypes: [prob.dtype]
        )

        return outputs[0]
    }
}
#endif

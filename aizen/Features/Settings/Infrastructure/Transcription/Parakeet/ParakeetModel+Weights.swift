import Foundation
#if arch(arm64)
import MLX
@preconcurrency import MLXNN

extension ParakeetTDT {
    /// Load weights from one or more safetensors files.
    nonisolated public func loadWeights(from urls: [URL]) throws {
        var mappedWeights: [String: MLXArray] = [:]

        for url in urls {
            let weights = try MLX.loadArrays(url: url)
            for (safetensorsKey, weight) in weights {
                if let swiftKey = mapSafetensorsKeyToSwiftPath(safetensorsKey) {
                    mappedWeights[swiftKey] = weight
                }
            }
        }

        let flatWeights = ModuleParameters.unflattened(mappedWeights)
        self.update(parameters: flatWeights)
    }

    nonisolated public func loadWeights(from url: URL) throws {
        try loadWeights(from: [url])
    }

    nonisolated func mapSafetensorsKeyToSwiftPath(_ safetensorsKey: String) -> String? {
        if safetensorsKey.hasPrefix("encoder.") {
            let encoderKey = String(safetensorsKey.dropFirst("encoder.".count))

            if encoderKey.hasPrefix("pre_encode.") {
                let preEncodeKey = String(encoderKey.dropFirst("pre_encode.".count))
                if preEncodeKey.hasPrefix("conv.") || preEncodeKey.hasPrefix("out.") {
                    return "encoder.preEncode.\(preEncodeKey)"
                }
            }

            if encoderKey.hasPrefix("layers.") {
                var layerKey = encoderKey
                layerKey = layerKey.replacingOccurrences(of: "norm_self_att", with: "normSelfAtt")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.linear_q", with: "selfAttn.wq")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.linear_k", with: "selfAttn.wk")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.linear_v", with: "selfAttn.wv")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.linear_out", with: "selfAttn.wo")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.linear_pos", with: "selfAttn.linearPos")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.pos_bias_u", with: "selfAttn.posBiasU")
                layerKey = layerKey.replacingOccurrences(of: "self_attn.pos_bias_v", with: "selfAttn.posBiasV")
                layerKey = layerKey.replacingOccurrences(of: "norm_conv", with: "normConv")
                layerKey = layerKey.replacingOccurrences(of: "conv.pointwise_conv1", with: "conv.pointwiseConv1")
                layerKey = layerKey.replacingOccurrences(of: "conv.depthwise_conv", with: "conv.depthwiseConv")
                layerKey = layerKey.replacingOccurrences(of: "conv.batch_norm", with: "conv.batchNorm")
                layerKey = layerKey.replacingOccurrences(of: "conv.pointwise_conv2", with: "conv.pointwiseConv2")
                layerKey = layerKey.replacingOccurrences(of: "norm_feed_forward1", with: "normFeedForward1")
                layerKey = layerKey.replacingOccurrences(of: "feed_forward1", with: "feedForward1")
                layerKey = layerKey.replacingOccurrences(of: "norm_feed_forward2", with: "normFeedForward2")
                layerKey = layerKey.replacingOccurrences(of: "feed_forward2", with: "feedForward2")
                layerKey = layerKey.replacingOccurrences(of: "norm_out", with: "normOut")
                return "encoder.\(layerKey)"
            }
        }

        if safetensorsKey.hasPrefix("decoder.") {
            var decoderKey = String(safetensorsKey.dropFirst("decoder.".count))
            decoderKey = decoderKey.replacingOccurrences(of: "prediction.embed", with: "embed")
            decoderKey = decoderKey.replacingOccurrences(of: "prediction.dec_rnn.lstm", with: "decRNN.lstmLayers")
            return "decoder.\(decoderKey)"
        }

        if safetensorsKey.hasPrefix("joint.") {
            var jointKey = String(safetensorsKey.dropFirst("joint.".count))
            jointKey = jointKey.replacingOccurrences(of: "enc_proj", with: "encLinear")
            jointKey = jointKey.replacingOccurrences(of: "pred_proj", with: "predLinear")
            jointKey = jointKey.replacingOccurrences(of: "joint_proj", with: "jointLinear")
            jointKey = jointKey.replacingOccurrences(of: "enc.", with: "encLinear.")
            jointKey = jointKey.replacingOccurrences(of: "pred.", with: "predLinear.")

            if jointKey.hasPrefix("joint_net.") {
                let jointNetKey = String(jointKey.dropFirst("joint_net.".count))
                if jointNetKey.hasPrefix("2.") {
                    let layerParam = String(jointNetKey.dropFirst("2.".count))
                    jointKey = "jointLinear.\(layerParam)"
                } else {
                    return nil
                }
            }

            return "joint.\(jointKey)"
        }

        return nil
    }
}
#endif

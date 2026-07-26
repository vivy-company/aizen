import AizenCore
import AizenSecurity
import Dispatch
import Foundation
import Network
import Security

public enum PairedTLSOptionsError: Swift.Error, Sendable, Equatable {
    case noAuthorizedDevices
}

/// TLS 1.3 options authenticated by PSKs derived from pinned paired identities.
public enum PairedTLSOptions {
    public static func server(
        host: HostPublicIdentity,
        hostIdentity: LocalCryptographicIdentity,
        authorizations: [DeviceAuthorization]
    ) throws -> NWProtocolTLS.Options {
        let authorized = authorizations.filter { $0.revokedAt == nil }.sorted { $0.device.deviceID.description < $1.device.deviceID.description }
        guard !authorized.isEmpty else { throw PairedTLSOptionsError.noAuthorizedDevices }
        let options = makeTLS13Options()
        let securityOptions = options.securityProtocolOptions
        for authorization in authorized {
            let key = try PairedTLSPreSharedKey.derive(hostID: host.hostID, device: authorization.device, hostIdentity: hostIdentity)
            sec_protocol_options_add_pre_shared_key(
                securityOptions,
                dispatchData(key),
                dispatchData(PairedTLSPreSharedKey.identity(for: authorization.device.deviceID))
            )
        }
        return options
    }

    public static func client(
        host: HostPublicIdentity,
        deviceID: DeviceID,
        deviceIdentity: LocalCryptographicIdentity
    ) throws -> NWProtocolTLS.Options {
        let options = makeTLS13Options()
        let key = try PairedTLSPreSharedKey.derive(host: host, deviceID: deviceID, deviceIdentity: deviceIdentity)
        sec_protocol_options_add_pre_shared_key(
            options.securityProtocolOptions,
            dispatchData(key),
            dispatchData(PairedTLSPreSharedKey.identity(for: deviceID))
        )
        return options
    }

    private static func makeTLS13Options() -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let securityOptions = options.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, .TLSv13)
        return options
    }

    private static func dispatchData(_ data: Data) -> __DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) as __DispatchData }
    }
}

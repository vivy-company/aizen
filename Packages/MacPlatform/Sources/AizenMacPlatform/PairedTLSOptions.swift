import AizenCore
import AizenSecurity
import Dispatch
import Foundation
import Network
import Security

/// TLS 1.3 options. Paired clients use PSKs; a bootstrap certificate keeps the
/// listener reachable until the first local pairing approval exists.
public enum PairedTLSOptions {
    public static func server(
        host: HostPublicIdentity,
        hostIdentity: LocalCryptographicIdentity,
        authorizations: [DeviceAuthorization]
    ) throws -> NWProtocolTLS.Options {
        let authorized = authorizations.filter { $0.revokedAt == nil }.sorted { $0.device.deviceID.description < $1.device.deviceID.description }
        let options = makeTLS13Options()
        let securityOptions = options.securityProtocolOptions
        sec_protocol_options_set_local_identity(securityOptions, try BootstrapTLSIdentity.make())
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
        // The Host uses a bootstrap certificate. The paired PSK and the signed Aizen
        // challenge immediately above Wire are the identity checks; a public PKI name
        // must not substitute for either of them.
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in
            complete(true)
        }, DispatchQueue(label: "win.aizen.remote-tls-verify"))
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

/// A per-listener certificate provides TLS confidentiality during first-device
/// bootstrap. The subsequent signed Wire challenge is what pins the Host to
/// the public identity carried by the QR invitation.
private enum BootstrapTLSIdentity {
    private enum Error: Swift.Error {
        case keyGenerationFailed
        case publicKeyUnavailable
        case certificateCreationFailed
        case identityCreationFailed
        case signatureFailed
        case invalidSignature
    }

    static func make(now: Date = Date()) throws -> sec_identity_t {
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: false]
        ] as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? Error.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error?.takeRetainedValue() ?? Error.publicKeyUnavailable
        }

        let certificateData = try SelfSignedCertificate.make(publicKey: publicKeyData, privateKey: privateKey, now: now)
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw Error.certificateCreationFailed
        }
        guard let identity = SecIdentityCreate(nil, certificate, privateKey), let protocolIdentity = sec_identity_create(identity) else {
            throw Error.identityCreationFailed
        }
        return protocolIdentity
    }

    private enum SelfSignedCertificate {
        private static let ecdsaWithSHA256 = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02])
        private static let commonName = Data([0x06, 0x03, 0x55, 0x04, 0x03])
        private static let ecPublicKey = Data([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
        private static let prime256v1 = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        private static let basicConstraints = Data([0x06, 0x03, 0x55, 0x1D, 0x13])
        private static let keyUsage = Data([0x06, 0x03, 0x55, 0x1D, 0x0F])

        static func make(publicKey: Data, privateKey: SecKey, now: Date) throws -> Data {
            guard publicKey.count == 65, publicKey.first == 0x04 else { throw Error.publicKeyUnavailable }
            var serial = Data(count: 16)
            let serialStatus = serial.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
            guard serialStatus == errSecSuccess else { throw Error.keyGenerationFailed }
            serial[0] &= 0x7F
            if serial.allSatisfy({ $0 == 0 }) { serial[15] = 1 }

            let algorithm = sequence(ecdsaWithSHA256)
            let name = sequence(set(sequence(commonName + utf8String("Aizen Host Bootstrap"))))
            let validity = sequence(utcTime(now) + utcTime(now.addingTimeInterval(86_400 * 366)))
            let subjectPublicKey = sequence(sequence(ecPublicKey + prime256v1) + bitString(publicKey))
            let extensions = explicit(3, sequence(
                sequence(basicConstraints + boolean(true) + octetString(sequence(Data()))) +
                sequence(keyUsage + boolean(true) + octetString(bitString(Data([0x80]))))
            ))
            let tbs = sequence(explicit(0, integer(Data([2]))) + integer(serial) + algorithm + name + validity + name + subjectPublicKey + extensions)
            var error: Unmanaged<CFError>?
            guard let rawSignature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error) as Data? else {
                throw error?.takeRetainedValue() ?? Error.signatureFailed
            }
            return sequence(tbs + algorithm + bitString(try derECDSASignature(rawSignature)))
        }

        private static func derECDSASignature(_ raw: Data) throws -> Data {
            // Security returns X9.62 DER on current Apple platforms. Keep the
            // raw 64-byte form as a compatibility fallback for older providers.
            if raw.first == 0x30, raw.count >= 8 { return raw }
            guard raw.count == 64 else { throw Error.invalidSignature }
            return sequence(integer(raw.prefix(32)) + integer(raw.suffix(32)))
        }

        private static func sequence(_ value: Data) -> Data { tagged(0x30, value) }
        private static func set(_ value: Data) -> Data { tagged(0x31, value) }
        private static func utf8String(_ value: String) -> Data { tagged(0x0C, Data(value.utf8)) }
        private static func boolean(_ value: Bool) -> Data { Data([0x01, 0x01, value ? 0xFF : 0x00]) }
        private static func octetString(_ value: Data) -> Data { tagged(0x04, value) }
        private static func bitString(_ value: Data) -> Data { tagged(0x03, Data([0]) + value) }
        private static func explicit(_ number: UInt8, _ value: Data) -> Data { tagged(0xA0 | number, value) }

        private static func integer<S: DataProtocol>(_ value: S) -> Data {
            var bytes = Data(value)
            while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
            if bytes.first.map({ $0 & 0x80 != 0 }) == true { bytes.insert(0, at: 0) }
            return tagged(0x02, bytes)
        }

        private static func utcTime(_ date: Date) -> Data {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            return tagged(0x17, Data(formatter.string(from: date).utf8))
        }

        private static func tagged(_ tag: UInt8, _ value: Data) -> Data {
            Data([tag]) + length(value.count) + value
        }

        private static func length(_ value: Int) -> Data {
            precondition(value >= 0)
            if value < 128 { return Data([UInt8(value)]) }
            var bytes: [UInt8] = []
            var remaining = value
            while remaining > 0 {
                bytes.insert(UInt8(remaining & 0xFF), at: 0)
                remaining >>= 8
            }
            return Data([0x80 | UInt8(bytes.count)]) + bytes
        }
    }
}

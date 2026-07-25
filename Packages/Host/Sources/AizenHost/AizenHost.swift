import AizenCore
import AizenWire

/// Host command/query composition. Mac-only runtime adapters stay outside this package.
public enum AizenHostModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
}

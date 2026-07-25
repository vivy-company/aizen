import Testing
@testable import AizenCore

@Test func productGenerationsStayIndependent() {
    #expect(AizenCoreModule.productVersion == "2.0.0")
    #expect(AizenCoreModule.protocolGeneration == 1)
    #expect(AizenCoreModule.storageSchemaVersion == 2)
}

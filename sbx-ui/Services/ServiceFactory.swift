import Foundation

struct ServiceFactory {
    static func create() -> any SbxServiceProtocol {
        if ProcessInfo.processInfo.environment["SBX_MOCK"] == "1" {
            return MockSbxService()
        }
        return RealSbxService()
    }
}

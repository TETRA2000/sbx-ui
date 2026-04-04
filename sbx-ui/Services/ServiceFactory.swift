import Foundation

struct ServiceFactory {
    static func create() -> any SbxServiceProtocol {
        return RealSbxService()
    }
}

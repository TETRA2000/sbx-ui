import Foundation

public struct ServiceFactory {
    public static func create() -> any SbxServiceProtocol {
        return RealSbxService()
    }
}

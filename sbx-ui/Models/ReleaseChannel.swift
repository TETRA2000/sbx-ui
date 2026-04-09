import Foundation

nonisolated enum ReleaseChannel: String, CaseIterable, Sendable {
    case canary
    case beta
    case stable

    static let current: ReleaseChannel = {
        #if CANARY
        .canary
        #elseif BETA
        .beta
        #elseif STABLE
        .stable
        #else
        .stable
        #endif
    }()

    var displayName: String {
        rawValue.capitalized
    }
}

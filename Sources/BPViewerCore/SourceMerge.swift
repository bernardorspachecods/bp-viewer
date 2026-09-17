import Foundation

public enum SourceMergeResult: Equatable, Sendable {
    case merged(String)
    case conflict(base: String, local: String, external: String)
}

public enum SourceThreeWayMerge {
    public static func resolve(
        base: String,
        local: String,
        external: String
    ) -> SourceMergeResult {
        if local == base { return .merged(external) }
        if external == base { return .merged(local) }
        if local == external { return .merged(local) }
        return .conflict(base: base, local: local, external: external)
    }
}

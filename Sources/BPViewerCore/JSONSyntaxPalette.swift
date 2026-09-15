import Foundation

public struct JSONSyntaxColorPalette: Equatable, Sendable {
    public let background: String
    public let foreground: String
    public let punctuation: String
    public let key: String
    public let string: String
    public let number: String
    public let literal: String
    public let invalid: String

    public init(isDark: Bool) {
        if isDark {
            self = Self.dark
        } else {
            self = Self.light
        }
    }

    public static let light = Self(
        background: "#FFFFFF",
        foreground: "#1F1F1F",
        punctuation: "#555555",
        key: "#005CC5",
        string: "#A31515",
        number: "#098658",
        literal: "#AF00DB",
        invalid: "#C00000"
    )

    public static let dark = Self(
        background: "#1E1E1E",
        foreground: "#F5F5F5",
        punctuation: "#BDBDBD",
        key: "#9CDCFE",
        string: "#CE9178",
        number: "#B5CEA8",
        literal: "#C586C0",
        invalid: "#FF6B6B"
    )

    public func color(for kind: JSONSyntaxTokenKind) -> String {
        switch kind {
        case .punctuation: punctuation
        case .key: key
        case .string: string
        case .number: number
        case .boolean, .null: literal
        case .invalid: invalid
        }
    }

    private init(
        background: String,
        foreground: String,
        punctuation: String,
        key: String,
        string: String,
        number: String,
        literal: String,
        invalid: String
    ) {
        self.background = background
        self.foreground = foreground
        self.punctuation = punctuation
        self.key = key
        self.string = string
        self.number = number
        self.literal = literal
        self.invalid = invalid
    }
}

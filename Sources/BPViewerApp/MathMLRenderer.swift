import Foundation

struct TeXMathMLRenderer: Sendable {
    func render(_ source: String, displayMode: Bool) -> String {
        var parser = TeXMathParser(source: source)
        let body = parser.parseSequence()
        let displayAttribute = displayMode ? " display=\"block\"" : ""
        return "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"\(displayAttribute)><mrow>\(body)</mrow></math>"
    }
}

private struct TeXMathParser {
    private let characters: [Character]
    private var index = 0

    init(source: String) {
        characters = Array(source)
    }

    mutating func parseSequence(stopAtClosingBrace: Bool = false) -> String {
        var result = ""

        while let character = peek {
            if stopAtClosingBrace, character == "}" {
                consume()
                break
            }

            if character.isWhitespace {
                consume()
                continue
            }

            result += parseElement()
        }

        return result
    }

    private mutating func parseElement() -> String {
        var base = parseAtom()
        var subscriptValue: String?
        var superscriptValue: String?

        while let character = peek, character == "_" || character == "^" {
            consume()
            let value = parseArgument()
            if character == "_" {
                subscriptValue = value
            } else {
                superscriptValue = value
            }
        }

        if let subscriptValue, let superscriptValue {
            base = "<msubsup>\(base)\(subscriptValue)\(superscriptValue)</msubsup>"
        } else if let subscriptValue {
            base = "<msub>\(base)\(subscriptValue)</msub>"
        } else if let superscriptValue {
            base = "<msup>\(base)\(superscriptValue)</msup>"
        }

        return base
    }

    private mutating func parseAtom() -> String {
        guard let character = consume() else { return "" }

        if character == "{" {
            return "<mrow>\(parseSequence(stopAtClosingBrace: true))</mrow>"
        }

        if character == "\\" {
            return parseCommand()
        }

        if character.isNumber {
            var value = String(character)
            while let next = peek, next.isNumber || next == "." {
                value.append(consume()!)
            }
            return "<mn>\(escape(value))</mn>"
        }

        if character.isLetter {
            return "<mi>\(escape(String(character)))</mi>"
        }

        let value = escape(String(character))
        switch character {
        case "(", ")", "[", "]", "|": return "<mo>\(value)</mo>"
        case "+", "-", "=", "<", ">", ",", ".", ":", ";", "!": return "<mo>\(value)</mo>"
        default: return "<mo>\(value)</mo>"
        }
    }

    private mutating func parseCommand() -> String {
        guard let first = peek else { return "" }

        if !first.isLetter {
            consume()
            switch first {
            case "\\": return "<mspace linebreak=\"newline\" />"
            case " ": return "<mspace width=\"0.25em\" />"
            case "!": return "<mspace width=\"-0.15em\" />"
            case "{", "}", "$", "%", "&", "_", "#": return "<mo>\(escape(String(first)))</mo>"
            default: return "<mtext>\\\(escape(String(first)))</mtext>"
            }
        }

        var command = ""
        while let next = peek, next.isLetter {
            command.append(consume()!)
        }

        switch command {
        case "frac", "dfrac", "tfrac":
            let numerator = parseArgument()
            let denominator = parseArgument()
            return "<mfrac>\(numerator)\(denominator)</mfrac>"
        case "sqrt":
            return "<msqrt>\(parseArgument())</msqrt>"
        case "mathbf", "boldsymbol":
            return "<mstyle mathvariant=\"bold\">\(parseArgument())</mstyle>"
        case "mathrm", "text", "operatorname":
            return "<mtext>\(plainTextArgument())</mtext>"
        case "overline":
            return "<mover accent=\"true\">\(parseArgument())<mo>¯</mo></mover>"
        case "hat":
            return "<mover accent=\"true\">\(parseArgument())<mo>^</mo></mover>"
        case "bar":
            return "<mover accent=\"true\">\(parseArgument())<mo>¯</mo></mover>"
        case "left", "right", "limits", "displaystyle", "textstyle":
            return peek == "{" ? parseArgument() : parseAtom()
        case "quad":
            return "<mspace width=\"1em\" />"
        case "qquad":
            return "<mspace width=\"2em\" />"
        case "alpha": return "<mi>α</mi>"
        case "beta": return "<mi>β</mi>"
        case "gamma": return "<mi>γ</mi>"
        case "delta": return "<mi>δ</mi>"
        case "epsilon": return "<mi>ϵ</mi>"
        case "theta": return "<mi>θ</mi>"
        case "lambda": return "<mi>λ</mi>"
        case "mu": return "<mi>μ</mi>"
        case "pi": return "<mi>π</mi>"
        case "sigma": return "<mi>σ</mi>"
        case "phi": return "<mi>ϕ</mi>"
        case "omega": return "<mi>ω</mi>"
        case "Gamma": return "<mo>Γ</mo>"
        case "Delta": return "<mo>Δ</mo>"
        case "Theta": return "<mo>Θ</mo>"
        case "Lambda": return "<mo>Λ</mo>"
        case "Sigma": return "<mo>Σ</mo>"
        case "Phi": return "<mo>Φ</mo>"
        case "Omega": return "<mo>Ω</mo>"
        case "sum": return "<mo>∑</mo>"
        case "prod": return "<mo>∏</mo>"
        case "int": return "<mo>∫</mo>"
        case "infty": return "<mo>∞</mo>"
        case "cdot": return "<mo>⋅</mo>"
        case "times": return "<mo>×</mo>"
        case "pm": return "<mo>±</mo>"
        case "le", "leq": return "<mo>≤</mo>"
        case "ge", "geq": return "<mo>≥</mo>"
        case "ne", "neq": return "<mo>≠</mo>"
        case "approx": return "<mo>≈</mo>"
        case "rightarrow": return "<mo>→</mo>"
        case "to": return "<mo>→</mo>"
        case "in": return "<mo>∈</mo>"
        case "notin": return "<mo>∉</mo>"
        case "forall": return "<mo>∀</mo>"
        case "exists": return "<mo>∃</mo>"
        case "partial": return "<mi>∂</mi>"
        case "nabla": return "<mi>∇</mi>"
        case "ell": return "<mi>ℓ</mi>"
        case "emptyset": return "<mi>∅</mi>"
        default:
            return "<mtext>\\\(escape(command))</mtext>"
        }
    }

    private mutating func parseArgument() -> String {
        skipSpaces()
        if peek == "{" {
            consume()
            return "<mrow>\(parseSequence(stopAtClosingBrace: true))</mrow>"
        }
        return parseElement()
    }

    private mutating func plainTextArgument() -> String {
        skipSpaces()
        guard peek == "{" else {
            return escape(consume().map(String.init) ?? "")
        }

        consume()
        var result = ""
        while let character = consume() {
            if character == "}" { break }
            result += escape(String(character))
        }
        return result
    }

    private mutating func skipSpaces() {
        while let character = peek, character.isWhitespace {
            consume()
        }
    }

    private var peek: Character? {
        guard index < characters.count else { return nil }
        return characters[index]
    }

    @discardableResult
    private mutating func consume() -> Character? {
        guard index < characters.count else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

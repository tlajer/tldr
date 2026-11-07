import Foundation

/// A parsed JSON value. Objects keep their key order and numbers keep their source text,
/// which `JSONSerialization` would lose.
indirect enum JSONNode: Equatable {
    case object([Member])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    struct Member: Equatable {
        let key: String
        let value: JSONNode
    }

    var nodeCount: Int {
        switch self {
        case .object(let members): 1 + members.reduce(0) { $0 + $1.value.nodeCount }
        case .array(let items): 1 + items.reduce(0) { $0 + $1.nodeCount }
        default: 1
        }
    }
}

struct SourceError: Error, Equatable {
    let message: String
    let line: Int
    let column: Int
}

/// Strict JSON plus the two extensions found in real config files (tsconfig, VS Code
/// settings, …): `//` and `/* */` comments, and trailing commas. `isLenient` reports
/// whether either was used.
struct JSONParser {
    private let bytes: [UInt8]
    private var i = 0
    private var depth = 0
    private(set) var isLenient = false

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    static func parse(_ text: String) throws -> (value: JSONNode, isLenient: Bool) {
        var parser = JSONParser(text)
        let value = try parser.parseDocument()
        return (value, parser.isLenient)
    }

    /// One value per non-empty line (JSON Lines / NDJSON).
    static func parseLines(_ text: String) throws -> [JSONNode] {
        var values: [JSONNode] = []
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where !line.allSatisfy(\.isWhitespace) {
            var parser = JSONParser(String(line))
            do {
                values.append(try parser.parseDocument())
            } catch let error as SourceError {
                throw SourceError(message: error.message, line: n + 1, column: error.column)
            }
        }
        return values
    }

    mutating func parseDocument() throws -> JSONNode {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }
        try skipWhitespace()
        let value = try parseValue()
        try skipWhitespace()
        if i < bytes.count { throw error("Unexpected \(describeCurrent()) after the end of the document") }
        return value
    }

    private mutating func parseValue() throws -> JSONNode {
        guard i < bytes.count else { throw error("Unexpected end of input, expected a value") }
        depth += 1
        defer { depth -= 1 }
        if depth > 1000 { throw error("Nesting is too deep") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
        default: throw error("Unexpected \(describeCurrent()), expected a value")
        }
    }

    private mutating func parseObject() throws -> JSONNode {
        i += 1
        var members: [JSONNode.Member] = []
        try skipWhitespace()
        if peek(UInt8(ascii: "}")) { i += 1; return .object(members) }
        while true {
            guard peek(UInt8(ascii: "\"")) else { throw error("Expected a property name in double quotes, found \(describeCurrent())") }
            let key = try parseString()
            try skipWhitespace()
            guard peek(UInt8(ascii: ":")) else { throw error("Expected ':' after property name, found \(describeCurrent())") }
            i += 1
            try skipWhitespace()
            members.append(.init(key: key, value: try parseValue()))
            try skipWhitespace()
            if peek(UInt8(ascii: ",")) {
                i += 1
                try skipWhitespace()
                if peek(UInt8(ascii: "}")) { isLenient = true; i += 1; return .object(members) }
            } else if peek(UInt8(ascii: "}")) {
                i += 1
                return .object(members)
            } else {
                throw error("Expected ',' or '}' in object, found \(describeCurrent())")
            }
        }
    }

    private mutating func parseArray() throws -> JSONNode {
        i += 1
        var items: [JSONNode] = []
        try skipWhitespace()
        if peek(UInt8(ascii: "]")) { i += 1; return .array(items) }
        while true {
            items.append(try parseValue())
            try skipWhitespace()
            if peek(UInt8(ascii: ",")) {
                i += 1
                try skipWhitespace()
                if peek(UInt8(ascii: "]")) { isLenient = true; i += 1; return .array(items) }
            } else if peek(UInt8(ascii: "]")) {
                i += 1
                return .array(items)
            } else {
                throw error("Expected ',' or ']' in array, found \(describeCurrent())")
            }
        }
    }

    private mutating func parseString() throws -> String {
        let start = i
        i += 1
        var buffer: [UInt8] = []
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case UInt8(ascii: "\""):
                i += 1
                return String(decoding: buffer, as: UTF8.self)
            case UInt8(ascii: "\\"):
                i += 1
                guard i < bytes.count else { break }
                let escape = bytes[i]
                i += 1
                switch escape {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): buffer.append(escape)
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try parseHex4()
                    if (0xD800...0xDBFF).contains(scalar), bytes[i...].starts(with: [UInt8(ascii: "\\"), UInt8(ascii: "u")]) {
                        let save = i
                        i += 2
                        let low = try parseHex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                    buffer.append(contentsOf: Array(String(Unicode.Scalar(scalar).map(Character.init) ?? "\u{FFFD}").utf8))
                default:
                    i -= 1
                    throw error("Invalid escape sequence '\\\(describe(escape))' in string")
                }
            case 0x00..<0x20:
                throw error(b == 0x0A ? "Unterminated string (newline before closing quote)" : "Unescaped control character in string")
            default:
                buffer.append(b)
                i += 1
            }
        }
        i = start
        throw error("Unterminated string")
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard i + 4 <= bytes.count,
              let value = UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16)
        else { throw error("Invalid \\u escape, expected four hex digits") }
        i += 4
        return value
    }

    private mutating func parseNumber() throws -> String {
        let start = i
        func digits() -> Int {
            let s = i
            while i < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) { i += 1 }
            return i - s
        }
        if peek(UInt8(ascii: "-")) { i += 1 }
        if peek(UInt8(ascii: "0")) {
            i += 1
        } else if digits() == 0 {
            throw error("Invalid number, expected a digit")
        }
        if peek(UInt8(ascii: ".")) {
            i += 1
            if digits() == 0 { throw error("Invalid number, expected a digit after '.'") }
        }
        if peek(UInt8(ascii: "e")) || peek(UInt8(ascii: "E")) {
            i += 1
            if peek(UInt8(ascii: "+")) || peek(UInt8(ascii: "-")) { i += 1 }
            if digits() == 0 { throw error("Invalid number, expected a digit in the exponent") }
        }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    private mutating func expectLiteral(_ literal: String) throws {
        let utf8 = Array(literal.utf8)
        guard bytes[i...].starts(with: utf8) else { throw error("Unexpected \(describeCurrent()), expected a value") }
        i += utf8.count
    }

    private mutating func skipWhitespace() throws {
        while i < bytes.count {
            switch bytes[i] {
            case 0x20, 0x09, 0x0A, 0x0D:
                i += 1
            case UInt8(ascii: "/") where i + 1 < bytes.count && bytes[i + 1] == UInt8(ascii: "/"):
                isLenient = true
                while i < bytes.count, bytes[i] != 0x0A { i += 1 }
            case UInt8(ascii: "/") where i + 1 < bytes.count && bytes[i + 1] == UInt8(ascii: "*"):
                isLenient = true
                let start = i
                i += 2
                while i + 1 < bytes.count, !(bytes[i] == UInt8(ascii: "*") && bytes[i + 1] == UInt8(ascii: "/")) { i += 1 }
                guard i + 1 < bytes.count else { i = start; throw error("Unterminated /* comment") }
                i += 2
            default:
                return
            }
        }
    }

    private func peek(_ byte: UInt8) -> Bool {
        i < bytes.count && bytes[i] == byte
    }

    private func describeCurrent() -> String {
        guard i < bytes.count else { return "end of input" }
        // Decode the whole character at i, not just its first byte.
        let end = min(i + 4, bytes.count)
        if let ch = String(decoding: bytes[i..<end], as: UTF8.self).first, ch != "\u{FFFD}" || bytes[i] < 0x80 {
            return "'\(ch)'"
        }
        return "'\(describe(bytes[i]))'"
    }

    private func describe(_ byte: UInt8) -> String {
        (0x21..<0x7F).contains(byte) ? String(UnicodeScalar(byte)) : String(format: "0x%02X", byte)
    }

    private func error(_ message: String) -> SourceError {
        let upTo = bytes[..<min(i, bytes.count)]
        let line = upTo.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        let lineStart = upTo.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        let column = String(decoding: bytes[lineStart..<min(i, bytes.count)], as: UTF8.self).count + 1
        return SourceError(message: message, line: line, column: column)
    }
}

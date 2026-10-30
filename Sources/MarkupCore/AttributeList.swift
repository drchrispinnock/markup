import Foundation

/// A Leanpub (Markua) attribute list alone on a line, such as
/// `{caption: "/etc/default/octez-node", format: ini}`, which sets
/// attributes of the block below it. Values may be quoted, with `\"` for a
/// quote inside. A heading's ID (`{#x}`) and a line without a `key: value`,
/// such as `{begin-hanging-paragraphs}`, aren't attribute lists.
public struct AttributeList: Equatable, Sendable {
    public var attributes: [String: String]

    public init?(line: some StringProtocol) {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        guard characters.count >= 2, characters.first == "{", characters.last == "}", characters[1] != "#" else { return nil }
        let inner = characters[1..<characters.count - 1]
        var attributes: [String: String] = [:]
        var index = inner.startIndex
        func skipSpaces() { while index < inner.endIndex, inner[index] == " " { index += 1 } }
        while true {
            skipSpaces()
            let keyStart = index
            while index < inner.endIndex, inner[index].isLetter || inner[index].isNumber || inner[index] == "_" || inner[index] == "-" {
                index += 1
            }
            guard index > keyStart else { return nil }
            let key = String(inner[keyStart..<index])
            skipSpaces()
            guard index < inner.endIndex, inner[index] == ":" else { return nil }
            index += 1
            skipSpaces()
            var value = ""
            if index < inner.endIndex, inner[index] == "\"" {
                index += 1
                while index < inner.endIndex, inner[index] != "\"" {
                    if inner[index] == "\\", index + 1 < inner.endIndex { index += 1 }
                    value.append(inner[index])
                    index += 1
                }
                guard index < inner.endIndex else { return nil }
                index += 1
                skipSpaces()
            } else {
                while index < inner.endIndex, inner[index] != "," {
                    value.append(inner[index])
                    index += 1
                }
                value = value.trimmingCharacters(in: .whitespaces)
            }
            attributes[key] = value
            guard index < inner.endIndex else { break }
            guard inner[index] == "," else { return nil }
            index += 1
        }
        self.attributes = attributes
    }

    public subscript(key: String) -> String? { attributes[key] }
}

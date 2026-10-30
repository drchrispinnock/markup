import Testing
@testable import MarkupCore

@Suite struct AttributeListTests {
    @Test func readsKeysAndValues() {
        let list = AttributeList(line: #"{caption: "/etc/default/octez-node", format: ini}"#)
        #expect(list?.attributes == ["caption": "/etc/default/octez-node", "format": "ini"])
        #expect(AttributeList(line: #" {caption: "a, \"b\"",width:50%} "#)?.attributes == ["caption": #"a, "b""#, "width": "50%"])
    }

    @Test func otherBracesAreNot() {
        for line in ["{#id}", "{begin-hanging-paragraphs}", "{}", "{caption: \"open}", "{a: 1 b: 2", "text {a: 1}"] {
            #expect(AttributeList(line: line) == nil, "\(line)")
        }
    }
}

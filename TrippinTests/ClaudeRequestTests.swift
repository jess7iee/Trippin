import Testing
import Foundation

struct ClaudeRequestTests {
    private let schema: [String: Any] = [
        "type": "object",
        "properties": ["b": ["type": "string"], "a": ["type": "integer"], "c": ["type": "number"]],
        "required": ["a", "b", "c"],
        "additionalProperties": false,
    ]

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func sameInputsGiveIdenticalBytes() throws {
        let blocks = [ClaudeRequest.Block(text: "Trip context", cached: true), .init(text: "Request")]
        let first = try ClaudeRequest.body(model: "m", system: "s", blocks: blocks, schema: schema, effort: "medium")
        for _ in 0..<20 {
            #expect(try ClaudeRequest.body(model: "m", system: "s", blocks: blocks, schema: schema, effort: "medium") == first)
        }
        // Keys are sorted, so "fallbacks" comes before "max_tokens" before "messages".
        let text = String(decoding: first, as: UTF8.self)
        let f = try #require(text.range(of: "\"fallbacks\"")), m = try #require(text.range(of: "\"max_tokens\""))
        #expect(f.lowerBound < m.lowerBound)
    }

    @Test func cacheBreakpointOnlyOnStablePart() throws {
        let data = try ClaudeRequest.body(model: "m", system: "s",
                                          blocks: [.init(text: "Trip context", cached: true), .init(text: "Request")],
                                          schema: schema, effort: "medium")
        let messages = try #require(json(data)["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect((content[0]["cache_control"] as? [String: String]) == ["type": "ephemeral"])
        #expect(content[1]["cache_control"] == nil)
    }

    @Test func uncachedPromptHasNoBreakpoint() throws {
        let data = try ClaudeRequest.body(model: "m", system: "s", blocks: [.init(text: "Email")], schema: schema, effort: "low")
        #expect(!String(decoding: data, as: UTF8.self).contains("cache_control"))
    }
}

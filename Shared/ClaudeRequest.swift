import Foundation

/// Builds Messages API request bodies so that the same inputs always produce the
/// same bytes. Prompt caching matches prefixes exactly, and Swift dictionaries
/// don't keep a stable key order, so keys are sorted.
enum ClaudeRequest {
    /// One text block of the user message. `cached` marks the end of a prefix that
    /// later requests are likely to repeat (e.g. the trip's plan), so the API can
    /// cache everything up to and including it.
    struct Block: Equatable {
        var text: String
        var cached = false
    }

    static func body(model: String, system: String, blocks: [Block],
                     schema: [String: Any], effort: String, maxTokens: Int = 16000) throws -> Data {
        let content: [[String: Any]] = blocks.filter { !$0.text.isEmpty }.map { block in
            var item: [String: Any] = ["type": "text", "text": block.text]
            if block.cached { item["cache_control"] = ["type": "ephemeral"] }
            return item
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            // If a safety classifier declines, let the API retry on a suitable model.
            "fallbacks": "default",
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

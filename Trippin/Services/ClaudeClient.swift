import Foundation

/// Calls the Claude Messages API over HTTPS (there is no official Swift SDK)
/// and decodes structured JSON output.
struct ClaudeClient {
    enum ClaudeError: LocalizedError {
        case missingKey
        case api(String)
        case refused
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your Claude API key in Settings to use this."
            case .api(let message): message
            case .refused: "Claude declined this request. Try rewording it."
            case .emptyResponse: "Claude didn't return a usable answer. Try again."
            }
        }
    }

    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var apiKey: String?

    init(apiKey: String? = KeychainStore.apiKey) {
        self.apiKey = apiKey
    }

    /// Sends one request whose answer must match `schema`, and decodes it as `T`.
    func structured<T: Decodable>(_ type: T.Type, system: String, prompt: String,
                                  schema: [String: Any], effort: String = "medium") async throws -> T {
        guard let apiKey else { throw ClaudeError.missingKey }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            // If a safety classifier declines, let the API retry on a suitable model.
            "fallbacks": "default",
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            switch status {
            case 401: throw ClaudeError.api("Your Claude API key was rejected. Check it in Settings.")
            case 429: throw ClaudeError.api("Claude is rate limited right now. Try again in a minute.")
            default: throw ClaudeError.api(apiError?.error.message ?? "Claude request failed (HTTP \(status)).")
            }
        }

        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        if message.stopReason == "refusal" { throw ClaudeError.refused }
        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8) else { throw ClaudeError.emptyResponse }
        do {
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            throw ClaudeError.emptyResponse
        }
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        var content: [Block]
        var stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable { var message: String }
        var error: Detail
    }
}

// MARK: - Reservation extraction

extension ClaudeClient {
    private struct ExtractionResult: Decodable {
        struct Item: Decodable {
            var kind: String
            var title: String
            var confirmationCode: String
            var start: String
            var end: String
            var location: String
            var localName: String
        }
        var reservations: [Item]
    }

    /// Pulls every reservation out of a confirmation email.
    func extractReservations(from email: String) async throws -> [ParsedReservation] {
        let kinds = ReservationKind.allCases.map(\.rawValue)
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": kinds],
                "title": ["type": "string", "description": "Short title, e.g. 'Flight UA 837 SFO → NRT' or 'Park Hyatt Tokyo'"],
                "confirmationCode": ["type": "string", "description": "Empty string if none"],
                "start": ["type": "string", "description": "Local start time as yyyy-MM-dd'T'HH:mm, or yyyy-MM-dd if no time. Empty if unknown."],
                "end": ["type": "string", "description": "Local end time in the same format, or empty"],
                "location": ["type": "string", "description": "Street address, or venue name and city, to find it on a map. For flights, the departure airport name."],
                "localName": ["type": "string", "description": "The hotel, restaurant, station or venue name as written in the local language and script, if the email shows it or you know it for certain; otherwise empty"],
            ],
            "required": ["kind", "title", "confirmationCode", "start", "end", "location", "localName"],
            "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["reservations": ["type": "array", "items": item]],
            "required": ["reservations"],
            "additionalProperties": false,
        ]
        let system = """
        You read travel confirmation emails and extract each booking: flights (one entry per flight leg), \
        hotels (start = check-in, end = check-out), restaurants, car rentals, trains and activities. \
        Use the local times written in the email. Return an empty list if the email has no booking.
        """
        let result = try await structured(ExtractionResult.self, system: system,
                                          prompt: "<email>\n\(email)\n</email>", schema: schema, effort: "low")
        return result.reservations.map { item in
            ParsedReservation(
                kind: ReservationKind(rawValue: item.kind) ?? .other,
                title: item.title,
                confirmationCode: item.confirmationCode.isEmpty ? nil : item.confirmationCode,
                start: Self.parseLocalDate(item.start),
                end: Self.parseLocalDate(item.end),
                address: item.location.isEmpty ? nil : item.location,
                localName: item.localName.isEmpty ? nil : item.localName
            )
        }
    }

    static func parseLocalDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

// MARK: - Local-language names

extension ClaudeClient {
    struct PlaceToName {
        var name: String
        var address: String?
    }

    private struct LocalNameResult: Decodable {
        struct Item: Decodable {
            var index: Int
            var localName: String
        }
        var names: [Item]
    }

    /// Returns each place's name as written locally, in the same order. Empty string when unknown.
    func localNames(for places: [PlaceToName], language: LocalLanguage, near destination: String) async throws -> [String] {
        guard !places.isEmpty else { return [] }
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "names": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "index": ["type": "integer"],
                            "localName": ["type": "string", "description": "Name in \(language.name), or empty if unsure"],
                        ],
                        "required": ["index", "localName"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["names"],
            "additionalProperties": false,
        ]
        let system = """
        You give the names of places as they are written locally in \(language.name): the name on the \
        building's signs, the official station name (e.g. 新宿駅, not a translation of "Shinjuku Station"), \
        or the name a taxi driver or local would recognize. Use the local script. If you don't know a \
        place's real local name, return an empty string rather than inventing a translation.
        """
        let list = places.enumerated().map { index, place in
            "\(index). \(place.name)" + (place.address.map { " — \($0)" } ?? "")
        }.joined(separator: "\n")
        let result = try await structured(LocalNameResult.self, system: system,
                                          prompt: "Places near \(destination):\n\(list)", schema: schema, effort: "low")
        var names = Array(repeating: "", count: places.count)
        for item in result.names where names.indices.contains(item.index) {
            names[item.index] = item.localName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return names
    }
}

// MARK: - Recommendations

struct Recommendation: Decodable, Identifiable, Hashable {
    var id: String { name + searchQuery }
    var name: String
    var localName: String
    var searchQuery: String
    var category: String
    var reason: String
    var forTodo: String
    var suggestedDay: Int
    var durationMinutes: Int
}

extension ClaudeClient {
    private struct RecommendationResult: Decodable {
        var recommendations: [Recommendation]
    }

    struct TripContext {
        var destination: String
        var startDate: Date
        var dayCount: Int
        /// Existing plan per day, e.g. ["Day 1 (Mon Mar 6): 15:00 check in Park Hyatt; Senso-ji"].
        var dayPlans: [String]
        var todos: [String]
        var extraRequest: String
    }

    func recommendations(for context: TripContext) async throws -> [Recommendation] {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Real place name"],
                "localName": ["type": "string", "description": "The name as written locally in the destination's language and script (e.g. 一蘭 渋谷店), or empty if it is the same or unknown"],
                "searchQuery": ["type": "string", "description": "Query that finds this exact place in Apple Maps, including neighborhood and city"],
                "category": ["type": "string", "description": "e.g. food, sight, shopping, errand, nightlife"],
                "reason": ["type": "string", "description": "One sentence on why it fits"],
                "forTodo": ["type": "string", "description": "The to-do item this answers, or 'general'"],
                "suggestedDay": ["type": "integer", "description": "1-based day number that keeps the day geographically tight"],
                "durationMinutes": ["type": "integer"],
            ],
            "required": ["name", "localName", "searchQuery", "category", "reason", "forTodo", "suggestedDay", "durationMinutes"],
            "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["recommendations": ["type": "array", "items": item]],
            "required": ["recommendations"],
            "additionalProperties": false,
        ]
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let system = """
        You are a local travel expert planning a trip. For each thing the traveler wants or needs to do, \
        suggest one to three specific, real, currently operating places in the destination. Assign each to \
        the day where it sits closest to that day's existing plans, so travel between stops stays short, and \
        avoid overloading any single day. Only suggest places you are confident exist.
        """
        let prompt = """
        Destination: \(context.destination)
        Trip: \(context.dayCount) days starting \(formatter.string(from: context.startDate))

        Current plan:
        \(context.dayPlans.isEmpty ? "(nothing planned yet)" : context.dayPlans.joined(separator: "\n"))

        Things the traveler wants or needs to do:
        \(context.todos.isEmpty ? "(none listed)" : context.todos.map { "- \($0)" }.joined(separator: "\n"))
        \(context.extraRequest.isEmpty ? "" : "\nAlso: \(context.extraRequest)")
        """
        let result = try await structured(RecommendationResult.self, system: system, prompt: prompt, schema: schema)
        return result.recommendations.map {
            var rec = $0
            rec.suggestedDay = min(max(rec.suggestedDay, 1), context.dayCount)
            return rec
        }
    }
}

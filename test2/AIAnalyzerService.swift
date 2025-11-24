import Foundation

actor AIAnalyzerService {

    struct ChatRequest: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let response_format: ResponseFormat

        struct ResponseFormat: Codable {
            let type: String
        }
    }

    struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String
                let content: String
            }
            let index: Int
            let message: Message
        }
        let choices: [Choice]
    }

    func analyze(ocrText: String, apiKey: String? = nil) async throws -> (parsed: AIAnalysisResponse, rawJSON: String) {
        let key = apiKey ?? (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(domain: "AIAnalyzerService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API key. Add OPENAI_API_KEY to Info.plist."])
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Instruct model to output ONLY the JSON object in the exact schema.
        let schema = """
        {
          "restrictions": [
            {
              "type": "street_cleaning",
              "daysOfWeek": [2],
              "startTime": "08:00",
              "endTime": "10:00",
              "notes": "No Parking 8AM–10AM Tue"
            }
          ]
        }
        Allowed types:
        street_cleaning, no_parking, metered, permit, other
        """

        let systemPrompt = """
        You are a parser for parking sign text. Output ONLY a single JSON object with this exact schema, no extra text:
        \(schema)
        Rules:
        - daysOfWeek: 0=Sun ... 6=Sat
        - Use 24h local time format HH:mm
        - If a window crosses midnight, keep endTime < startTime; the client handles overnight.
        - Choose type from allowed types only.
        """

        let userPrompt = """
        OCR TEXT:
        \(ocrText)
        """

        let body = ChatRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            response_format: .init(type: "json_object")
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AIAnalyzerService", code: -2, userInfo: [NSLocalizedDescriptionKey: "OpenAI error: \(text)"])
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw NSError(domain: "AIAnalyzerService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No content from AI"])
        }

        // content should be the JSON object as a string
        let parsed = try JSONDecoder().decode(AIAnalysisResponse.self, from: Data(content.utf8))
        return (parsed, content)
    }
}

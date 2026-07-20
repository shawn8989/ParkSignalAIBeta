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
    
    // Performs the HTTP request with a timeout and basic retry for transient errors.
    private func performRequest(_ request: URLRequest, retries: Int = 1) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "AIAnalyzerService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            if http.statusCode == 429 || (500...599).contains(http.statusCode) {
                if retries > 0 {
                    try await Task.sleep(nanoseconds: 300_000_000) // 0.3s backoff
                    return try await performRequest(request, retries: retries - 1)
                }
            }
            return (data, http)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut, retries > 0 {
                try await Task.sleep(nanoseconds: 300_000_000)
                return try await performRequest(request, retries: retries - 1)
            }
            throw error
        }
    }

    struct AnalyzeDebugResult {
        let parsed: AIAnalysisResponse
        let rawJSON: String
        let httpStatus: Int
        let requestJSON: String
        let responseBody: String
    }

    func analyze(ocrText: String, apiKey: String? = nil) async throws -> (parsed: AIAnalysisResponse, rawJSON: String) {
        var keySource = "none"
        let trimmedParam = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plistKey = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (trimmedParam?.isEmpty == false ? trimmedParam : nil)
            ?? (envKey?.isEmpty == false ? envKey : nil)
            ?? (plistKey?.isEmpty == false ? plistKey : nil)
        if trimmedParam != nil, trimmedParam?.isEmpty == false { keySource = "param" }
        else if envKey != nil, envKey?.isEmpty == false { keySource = "env" }
        else if plistKey != nil, plistKey?.isEmpty == false { keySource = "plist" }
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(
                domain: "AIAnalyzerService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API key. Provide OPENAI_API_KEY via: (1) function parameter, (2) Run scheme environment variable, or (3) Info.plist value expanded from a build setting."]
            )
        }
        print("AIAnalyzerService: Resolved API key source = \(keySource)")
        print("AIAnalyzerService: Using API key (masked) = \(maskKey(apiKey))")

        // Debug: which API key source is used
//        print("AIAnalyzerService: Using API key from Info.plist? \(key != nil)")

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
              "durationMinutes": null,
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
        - If the sign states a time limit like "3 HOUR PARKING" or "90 MINUTES", set durationMinutes accordingly and set startTime and endTime to "00:00". Do NOT fabricate start/end times.
        - If both a specific window and a time limit are present, prefer the explicit window and set durationMinutes to null.
        - If days aren’t explicitly stated but implied (e.g., Mon-Fri), infer them; otherwise leave empty.
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
        
        print("AIAnalyzerService: Performing OpenAI request (analyze)")
        let (data, http) = try await performRequest(request)
        print("AIAnalyzerService: OpenAI HTTP status = \(http.statusCode)")
        print("AIAnalyzerService: OpenAI response prefix = \(String(data: data.prefix(120), encoding: .utf8) ?? "<non-utf8>")")

        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AIAnalyzerService", code: -2, userInfo: [NSLocalizedDescriptionKey: "OpenAI error (status: \(http.statusCode)): \(text)"])
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw NSError(domain: "AIAnalyzerService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No content from AI"])
        }

        // content should be the JSON object as a string
        let parsed = try JSONDecoder().decode(AIAnalysisResponse.self, from: Data(content.utf8))
        return (parsed, content)
    }
    
    func analyzeWithDebug(ocrText: String, apiKey: String? = nil) async throws -> AnalyzeDebugResult {
        var keySource = "none"
        let trimmedParam = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plistKey = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (trimmedParam?.isEmpty == false ? trimmedParam : nil)
            ?? (envKey?.isEmpty == false ? envKey : nil)
            ?? (plistKey?.isEmpty == false ? plistKey : nil)
        if trimmedParam != nil, trimmedParam?.isEmpty == false { keySource = "param" }
        else if envKey != nil, envKey?.isEmpty == false { keySource = "env" }
        else if plistKey != nil, plistKey?.isEmpty == false { keySource = "plist" }
        guard let apiKey = key, !apiKey.isEmpty else {
            throw NSError(
                domain: "AIAnalyzerService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API key. Provide OPENAI_API_KEY via: (1) function parameter, (2) Run scheme environment variable, or (3) Info.plist value expanded from a build setting."]
            )
        }
        print("AIAnalyzerService: Resolved API key source = \(keySource)")
        print("AIAnalyzerService: Using API key (masked) = \(maskKey(apiKey))")

        // Debug: which API key source is used
//        print("AIAnalyzerService: Using API key (debug) from Info.plist? \(apiKey.isEmpty == false)")

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let schema = """
        {
          "restrictions": [
            {
              "type": "street_cleaning",
              "daysOfWeek": [2],
              "startTime": "08:00",
              "endTime": "10:00",
              "durationMinutes": null,
              "notes": "No Parking 8AM–10AM Tue"
            }
          ]
        }
        Allowed types:
        street_cleaning, no_parking, metered, permit, other
        """

        // Add light few-shot guidance for common patterns
        let examples = """
        Example 1 OCR:\nNO PARKING\nTUE 8AM-10AM\nSTREET CLEANING\nOutput:\n{"restrictions":[{"type":"street_cleaning","daysOfWeek":[2],"startTime":"08:00","endTime":"10:00","durationMinutes":null,"notes":"NO PARKING TUE 8AM-10AM STREET CLEANING"}]}

        Example 2 OCR:\n2 HR PARKING\n9AM-6PM MON-FRI\nOutput:\n{"restrictions":[{"type":"metered","daysOfWeek":[1,2,3,4,5],"startTime":"09:00","endTime":"18:00","durationMinutes":null,"notes":"2 HR PARKING 9AM-6PM MON-FRI"}]}
        """

        let systemPrompt = """
        You are a parser for parking sign text. Output ONLY a single JSON object with this exact schema, no extra text:
        \(schema)
        Rules:
        - daysOfWeek: 0=Sun ... 6=Sat
        - Use 24h local time format HH:mm
        - If a window crosses midnight, keep endTime < startTime; the client handles overnight.
        - Choose type from allowed types only.
        - If the sign states a time limit like "3 HOUR PARKING" or "90 MINUTES", set durationMinutes accordingly and set startTime and endTime to "00:00". Do NOT fabricate start/end times.
        - If both a specific window and a time limit are present, prefer the explicit window and set durationMinutes to null.
        - If the text clearly indicates a restriction but omits days, infer the most likely days from ranges like Mon-Fri or Sat-Sun; otherwise leave empty.
        \n\(examples)
        """

        let userPrompt = """
        OCR TEXT:\n\(ocrText)
        """

        let body = ChatRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            response_format: .init(type: "json_object")
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestJSONData = try encoder.encode(body)
        let requestJSONString = String(data: requestJSONData, encoding: .utf8) ?? ""
        request.httpBody = requestJSONData

        print("AIAnalyzerService: Performing OpenAI request (debug)")
        let (data, http) = try await performRequest(request)
        let httpStatus = http.statusCode
        print("AIAnalyzerService: OpenAI HTTP status = \(http.statusCode)")
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        print("AIAnalyzerService: OpenAI response prefix = \(String(data: data.prefix(120), encoding: .utf8) ?? "<non-utf8>")")

        guard (200...299).contains(httpStatus) else {
            throw NSError(domain: "AIAnalyzerService", code: -2, userInfo: [NSLocalizedDescriptionKey: "OpenAI error (status: \(httpStatus)): \(responseBody)"])
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw NSError(domain: "AIAnalyzerService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No content from AI"])
        }

        let parsed = try JSONDecoder().decode(AIAnalysisResponse.self, from: Data(content.utf8))
        return AnalyzeDebugResult(parsed: parsed, rawJSON: content, httpStatus: httpStatus, requestJSON: requestJSONString, responseBody: responseBody)
    }
    
    private func maskKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 8 { return "••••" }
        let start = trimmed.prefix(4)
        let end = trimmed.suffix(4)
        return String(start) + "••••" + String(end)
    }
}


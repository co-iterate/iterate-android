import Foundation

struct MCPMessage: Identifiable, Codable {
    let id: String
    let messageType: String
    let payload: MCPPayload?
    let timestamp: Date
    
    init(id: String = UUID().uuidString, messageType: String, payload: MCPPayload?, timestamp: Date = Date()) {
        self.id = id
        self.messageType = messageType
        self.payload = payload
        self.timestamp = timestamp
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case messageType = "message_type"
        case payload
        case timestamp
    }
}

struct MCPPayload: Codable {
    let request: MCPRequest?
    let response: MCPResponse?
    let customPrompts: CustomPrompts?
    let ghostSuggestions: GhostSuggestionStore?
    let quotaSnapshot: QuotaSnapshot?
    let quotaProviders: [UsageQuotaProvider]?
    let quotaStatusLabel: String?
    let liveGoal: LiveGoalSnapshot?

    init(
        request: MCPRequest?,
        response: MCPResponse?,
        customPrompts: CustomPrompts?,
        ghostSuggestions: GhostSuggestionStore? = nil,
        quotaSnapshot: QuotaSnapshot? = nil,
        quotaProviders: [UsageQuotaProvider]? = nil,
        quotaStatusLabel: String? = nil,
        liveGoal: LiveGoalSnapshot? = nil
    ) {
        self.request = request
        self.response = response
        self.customPrompts = customPrompts
        self.ghostSuggestions = ghostSuggestions
        self.quotaSnapshot = quotaSnapshot
        self.quotaProviders = quotaProviders
        self.quotaStatusLabel = quotaStatusLabel
        self.liveGoal = liveGoal
    }
}

struct LiveGoalSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let phase: String?
    let statusText: String?
    let progressPercent: Double?
    let progressSource: String?
    let progressLabel: String?
    let planTotal: Int?
    let planCompleted: Int?
    let tokensUsed: Int64?
    let tokenBudget: Int64?
    let timeUsedSeconds: Int64?
    let startedAtMs: Int64
    let updatedAtMs: Int64?
    let completedAtMs: Int64?
    let elapsedMs: Int64?
    let projectPath: String?
    let requestId: String?
    let codexThreadId: String?
    let codexDeeplink: String?
    let lastCodexEventAtMs: Int64?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case goalId = "goal_id"
        case title
        case status
        case phase
        case statusText = "status_text"
        case progressPercent = "progress_percent"
        case progressSource = "progress_source"
        case progressLabel = "progress_label"
        case planTotal = "plan_total"
        case planCompleted = "plan_completed"
        case tokensUsed = "tokens_used"
        case tokenBudget = "token_budget"
        case timeUsedSeconds = "time_used_seconds"
        case startedAtMs = "started_at_ms"
        case updatedAtMs = "updated_at_ms"
        case completedAtMs = "completed_at_ms"
        case elapsedMs = "elapsed_ms"
        case projectPath = "project_path"
        case requestId = "request_id"
        case codexThreadId = "codex_thread_id"
        case codexDeeplink = "codex_deeplink"
        case lastCodexEventAtMs = "last_codex_event_at_ms"
        case source
    }

    init(
        id: String,
        title: String,
        status: String,
        phase: String? = nil,
        statusText: String? = nil,
        progressPercent: Double? = nil,
        progressSource: String? = nil,
        progressLabel: String? = nil,
        planTotal: Int? = nil,
        planCompleted: Int? = nil,
        tokensUsed: Int64? = nil,
        tokenBudget: Int64? = nil,
        timeUsedSeconds: Int64? = nil,
        startedAtMs: Int64,
        updatedAtMs: Int64? = nil,
        completedAtMs: Int64? = nil,
        elapsedMs: Int64? = nil,
        projectPath: String? = nil,
        requestId: String? = nil,
        codexThreadId: String? = nil,
        codexDeeplink: String? = nil,
        lastCodexEventAtMs: Int64? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.phase = phase
        self.statusText = statusText
        self.progressPercent = progressPercent
        self.progressSource = progressSource
        self.progressLabel = progressLabel
        self.planTotal = planTotal
        self.planCompleted = planCompleted
        self.tokensUsed = tokensUsed
        self.tokenBudget = tokenBudget
        self.timeUsedSeconds = timeUsedSeconds
        self.startedAtMs = startedAtMs
        self.updatedAtMs = updatedAtMs
        self.completedAtMs = completedAtMs
        self.elapsedMs = elapsedMs
        self.projectPath = projectPath
        self.requestId = requestId
        self.codexThreadId = codexThreadId
        self.codexDeeplink = codexDeeplink
        self.lastCodexEventAtMs = lastCodexEventAtMs
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .goalId)
            ?? UUID().uuidString

        self.init(
            id: decodedId,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "Goal",
            status: try container.decodeIfPresent(String.self, forKey: .status) ?? "running",
            phase: try container.decodeIfPresent(String.self, forKey: .phase),
            statusText: try container.decodeIfPresent(String.self, forKey: .statusText),
            progressPercent: try container.decodeIfPresent(Double.self, forKey: .progressPercent),
            progressSource: try container.decodeIfPresent(String.self, forKey: .progressSource),
            progressLabel: try container.decodeIfPresent(String.self, forKey: .progressLabel),
            planTotal: try container.decodeIfPresent(Int.self, forKey: .planTotal),
            planCompleted: try container.decodeIfPresent(Int.self, forKey: .planCompleted),
            tokensUsed: try container.decodeIfPresent(Int64.self, forKey: .tokensUsed),
            tokenBudget: try container.decodeIfPresent(Int64.self, forKey: .tokenBudget),
            timeUsedSeconds: try container.decodeIfPresent(Int64.self, forKey: .timeUsedSeconds),
            startedAtMs: try container.decodeIfPresent(Int64.self, forKey: .startedAtMs) ?? 0,
            updatedAtMs: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMs),
            completedAtMs: try container.decodeIfPresent(Int64.self, forKey: .completedAtMs),
            elapsedMs: try container.decodeIfPresent(Int64.self, forKey: .elapsedMs),
            projectPath: try container.decodeIfPresent(String.self, forKey: .projectPath),
            requestId: try container.decodeIfPresent(String.self, forKey: .requestId),
            codexThreadId: try container.decodeIfPresent(String.self, forKey: .codexThreadId),
            codexDeeplink: try container.decodeIfPresent(String.self, forKey: .codexDeeplink),
            lastCodexEventAtMs: try container.decodeIfPresent(Int64.self, forKey: .lastCodexEventAtMs),
            source: try container.decodeIfPresent(String.self, forKey: .source)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(id, forKey: .goalId)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encodeIfPresent(statusText, forKey: .statusText)
        try container.encodeIfPresent(progressPercent, forKey: .progressPercent)
        try container.encodeIfPresent(progressSource, forKey: .progressSource)
        try container.encodeIfPresent(progressLabel, forKey: .progressLabel)
        try container.encodeIfPresent(planTotal, forKey: .planTotal)
        try container.encodeIfPresent(planCompleted, forKey: .planCompleted)
        try container.encodeIfPresent(tokensUsed, forKey: .tokensUsed)
        try container.encodeIfPresent(tokenBudget, forKey: .tokenBudget)
        try container.encodeIfPresent(timeUsedSeconds, forKey: .timeUsedSeconds)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encodeIfPresent(updatedAtMs, forKey: .updatedAtMs)
        try container.encodeIfPresent(completedAtMs, forKey: .completedAtMs)
        try container.encodeIfPresent(elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(projectPath, forKey: .projectPath)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(codexThreadId, forKey: .codexThreadId)
        try container.encodeIfPresent(codexDeeplink, forKey: .codexDeeplink)
        try container.encodeIfPresent(lastCodexEventAtMs, forKey: .lastCodexEventAtMs)
        try container.encodeIfPresent(source, forKey: .source)
    }
}

struct GhostSuggestionStore: Codable {
    let version: Int?
    let defaultSeedVersion: Int?
    let updatedAt: String?
    let suggestions: [GhostSuggestionItem]

    enum CodingKeys: String, CodingKey {
        case version
        case defaultSeedVersion
        case updatedAt
        case suggestions
    }
}

struct GhostSuggestionItem: Codable, Identifiable {
    let rawId: String?
    let key: String
    let description: String
    let enabled: Bool
    let sortOrder: Int

    var id: String { rawId ?? key }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case key
        case description
        case enabled
        case sortOrder = "sort_order"
    }
}

struct UsageQuotaProvider: Codable, Identifiable {
    let id: String
    let name: String
    let accountLabel: String?
    let color: String?
    let iconUrl: String?
    let summary: String
    let updatedAt: String?
    let metrics: [UsageQuotaMetric]
}

struct UsageQuotaMetric: Codable, Identifiable {
    let label: String
    let remaining: Int
    let resetLabel: String?
    let resetAtMs: Int64?

    var id: String { label }
}

struct QuotaSnapshot: Codable {
    let status: String
    let statusLabel: String
    let providers: [UsageQuotaProvider]
    let primary: QuotaSnapshotMetric?
    let secondary: QuotaSnapshotMetric?
    let updatedAtMs: Int64
    let staleAfterMs: Int64
    let source: String
    let error: String?
}

struct QuotaSnapshotMetric: Codable, Identifiable, Equatable {
    let providerId: String
    let providerName: String
    let providerSummary: String?
    let accountLabel: String?
    let label: String
    let remaining: Int
    let resetLabel: String?
    let resetAtMs: Int64?

    var id: String { "\(providerId):\(label)" }
}

struct CustomPrompts: Codable {
    let prompts: [PromptItem]?
}

struct PromptItem: Codable, Identifiable {
    let rawId: String?
    let name: String
    let content: String
    let type: String?
    var currentState: Bool?
    var isActive: Bool?
    let templateTrue: String?
    let templateFalse: String?

    var id: String { rawId ?? name }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case name, content, type
        case currentState = "current_state"
        case isActive = "is_active"
        case templateTrue = "template_true"
        case templateFalse = "template_false"
    }
}

struct MCPRequest: Codable {
    let requestId: String?
    let message: String?
    let browserAiResponse: String?
    let projectPath: String?
    let predefinedOptions: [String]?
    let inputPlaceholder: String?
    let timelineRouteId: String?
    let conversationRouteId: String?
    let codexThreadId: String?
    
    enum CodingKeys: String, CodingKey {
        case requestId = "id"
        case message
        case browserAiResponse = "browser_ai_response"
        case projectPath = "project_path"
        case predefinedOptions = "predefined_options"
        case inputPlaceholder = "input_placeholder"
        case timelineRouteId = "timeline_route_id"
        case conversationRouteId = "conversation_route_id"
        case codexThreadId = "codex_thread_id"
    }

    init(
        requestId: String? = nil,
        message: String? = nil,
        browserAiResponse: String? = nil,
        projectPath: String? = nil,
        predefinedOptions: [String]? = nil,
        inputPlaceholder: String? = nil,
        timelineRouteId: String? = nil,
        conversationRouteId: String? = nil,
        codexThreadId: String? = nil
    ) {
        self.requestId = requestId
        self.message = message
        self.browserAiResponse = browserAiResponse
        self.projectPath = projectPath
        self.predefinedOptions = predefinedOptions
        self.inputPlaceholder = inputPlaceholder
        self.timelineRouteId = timelineRouteId
        self.conversationRouteId = conversationRouteId
        self.codexThreadId = codexThreadId
    }

    var timelineRouteKey: String? {
        [
            timelineRouteId,
            conversationRouteId,
            codexThreadId,
            requestId
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct MCPResponse: Codable {
    let selectedOption: String?
    let userInput: String?
    
    enum CodingKeys: String, CodingKey {
        case selectedOption = "selected_option"
        case userInput = "user_input"
    }
}

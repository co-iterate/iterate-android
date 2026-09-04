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
    let projectPath: String?
    let predefinedOptions: [String]?
    let inputPlaceholder: String?
    let mcpHostId: String?
    let mcpHostLabel: String?
    let hostSessionId: String?
    let invocationId: String?
    let projectId: String?
    let projectDisplayName: String?
    let taskId: String?
    let taskDisplayName: String?
    let createdAt: String?
    let stateRevision: Int?
    let deadline: String?

    init(
        requestId: String?,
        message: String?,
        projectPath: String?,
        predefinedOptions: [String]?,
        inputPlaceholder: String?,
        mcpHostId: String? = nil,
        mcpHostLabel: String? = nil,
        hostSessionId: String? = nil,
        invocationId: String? = nil,
        projectId: String? = nil,
        projectDisplayName: String? = nil,
        taskId: String? = nil,
        taskDisplayName: String? = nil,
        createdAt: String? = nil,
        stateRevision: Int? = nil,
        deadline: String? = nil
    ) {
        self.requestId = requestId
        self.message = message
        self.projectPath = projectPath
        self.predefinedOptions = predefinedOptions
        self.inputPlaceholder = inputPlaceholder
        self.mcpHostId = mcpHostId
        self.mcpHostLabel = mcpHostLabel
        self.hostSessionId = hostSessionId
        self.invocationId = invocationId
        self.projectId = projectId
        self.projectDisplayName = projectDisplayName
        self.taskId = taskId
        self.taskDisplayName = taskDisplayName
        self.createdAt = createdAt
        self.stateRevision = stateRevision
        self.deadline = deadline
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "id"
        case message
        case projectPath = "project_path"
        case predefinedOptions = "predefined_options"
        case inputPlaceholder = "input_placeholder"
        case mcpHostId = "mcp_host_id"
        case mcpHostLabel = "mcp_host_label"
        case hostSessionId = "host_session_id"
        case invocationId = "invocation_id"
        case projectId = "project_id"
        case projectDisplayName = "project_display_name"
        case taskId = "task_id"
        case taskDisplayName = "task_display_name"
        case createdAt = "created_at"
        case stateRevision = "state_revision"
        case deadline
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

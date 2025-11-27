import Foundation

/// AI service configuration model
public struct AIConfig: Codable {
    public let provider: AIProvider
    public let region: String?
    public let model: String
    public let credentials: AICredentials?
    public let options: [String: String]?
    
    public init(
        provider: AIProvider,
        region: String? = nil,
        model: String,
        credentials: AICredentials? = nil,
        options: [String: String]? = nil
    ) {
        self.provider = provider
        self.region = region
        self.model = model
        self.credentials = credentials
        self.options = options
    }
}

/// Supported AI providers
public enum AIProvider: String, Codable {
    case bedrock
    case gemini
    case openai
}

/// AI service credentials
public struct AICredentials: Codable {
    public let accessKeyId: String?
    public let secretAccessKey: String?
    public let apiKey: String?
    
    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, apiKey: String? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.apiKey = apiKey
    }
}

/// AWS Bedrock specific configuration
public struct BedrockConfig {
    public let region: String
    public let model: BedrockModel
    public let accessKeyId: String
    public let secretAccessKey: String
    
    public init(region: String = "us-east-1", model: BedrockModel = .claude45Sonnet, accessKeyId: String, secretAccessKey: String) {
        self.region = region
        self.model = model
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
    }
    
    public var aiConfig: AIConfig {
        AIConfig(
            provider: .bedrock,
            region: region,
            model: model.rawValue,
            credentials: AICredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
        )
    }
}

/// Bedrock model identifiers
public enum BedrockModel: String {
    case claude45Sonnet = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    case claude45Haiku = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}


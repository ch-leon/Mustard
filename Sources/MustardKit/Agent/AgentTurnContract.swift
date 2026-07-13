import Foundation

public enum AgentTurnOutcome: String, Codable, Equatable, Sendable {
    case completed
    case needsInput = "needs_input"
    case failed
    case cancelled
    case requiresConnectedWorker = "requires_connected_worker"
}

public enum AgentRetryDisposition: String, Codable, Equatable, Sendable {
    case none
    case safe
    case backoff
    case uncertain
}

public struct AgentArtifact: Codable, Equatable, Sendable {
    public let label: String
    public let url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}

public struct AgentTurnResult: Codable, Equatable, Sendable {
    public let outcome: AgentTurnOutcome
    public let message: String
    public let questions: [String]
    public let summary: String
    public let artifacts: [AgentArtifact]
    public let retryDisposition: AgentRetryDisposition
    public let errorCategory: String?
    public let connectedCapability: String?
}

public enum AgentTurnContract {
    public static let jsonSchema = #"""
    {
      "type":"object",
      "additionalProperties":false,
      "properties":{
        "outcome":{"type":"string","enum":["completed","needs_input","failed","cancelled","requires_connected_worker"]},
        "message":{"type":"string"},
        "questions":{"type":"array","items":{"type":"string"}},
        "summary":{"type":"string"},
        "artifacts":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"label":{"type":"string"},"url":{"type":"string"}},"required":["label","url"]}},
        "retryDisposition":{"type":"string","enum":["none","safe","backoff","uncertain"]},
        "errorCategory":{"type":["string","null"]},
        "connectedCapability":{"type":["string","null"]}
      },
      "required":["outcome","message","questions","summary","artifacts","retryDisposition"]
    }
    """#

    public static func decode(_ text: String) throws -> AgentTurnResult {
        let data = Data(text.utf8)
        try validateNoUnknownProperties(in: data)
        return try JSONDecoder().decode(AgentTurnResult.self, from: data)
    }

    public static func workerContract() throws -> String {
        let url = Bundle.module.url(
            forResource: "MustardAgentContract",
            withExtension: "md",
            subdirectory: "Prompts"
        ) ?? Bundle.module.url(
            forResource: "MustardAgentContract",
            withExtension: "md"
        )
        guard let url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func validateNoUnknownProperties(in data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        let allowedResultKeys: Set<String> = [
            "outcome", "message", "questions", "summary", "artifacts",
            "retryDisposition", "errorCategory", "connectedCapability",
        ]
        guard Set(object.keys).isSubset(of: allowedResultKeys) else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        guard let artifacts = object["artifacts"] as? [[String: Any]] else { return }
        let allowedArtifactKeys: Set<String> = ["label", "url"]
        guard artifacts.allSatisfy({ Set($0.keys).isSubset(of: allowedArtifactKeys) }) else {
            throw CocoaError(.propertyListReadCorrupt)
        }
    }
}

//
//  Prompt.swift
//  SwiftMCP
//
//  Prompt capability definitions
//

import Foundation

// MARK: - Prompt Definition

public struct MCPPrompt: Codable, Hashable, @unchecked Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let arguments: [MCPPromptArgument]?
    public let outputSchema: [String: Any]?
    
    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        arguments: [MCPPromptArgument]? = nil,
        outputSchema: [String: Any]? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
        self.outputSchema = outputSchema
    }
    
    // Hashable conformance
    public static func == (lhs: MCPPrompt, rhs: MCPPrompt) -> Bool {
        lhs.name == rhs.name
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case name, title, description, arguments, outputSchema
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        arguments = try container.decodeIfPresent([MCPPromptArgument].self, forKey: .arguments)
        
        if let schemaData = try container.decodeIfPresent(AnyCodable.self, forKey: .outputSchema) {
            outputSchema = schemaData.value as? [String: Any]
        } else {
            outputSchema = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(arguments, forKey: .arguments)
        
        if let schema = outputSchema {
            try container.encode(AnyCodable(schema), forKey: .outputSchema)
        }
    }
}

// MARK: - Prompt Argument

public struct MCPPromptArgument: Codable, Hashable, Sendable {
    public let name: String
    public let description: String?
    public let required: Bool?
    
    public init(name: String, description: String? = nil, required: Bool? = nil) {
        self.name = name
        self.description = description
        self.required = required
    }
}

// MARK: - Prompt Message

public struct MCPPromptMessage: Codable, Sendable {
    public let role: String
    public let content: MCPContent
    
    public init(role: String, content: MCPContent) {
        self.role = role
        self.content = content
    }
    
    public static func user(_ text: String) -> MCPPromptMessage {
        MCPPromptMessage(role: "user", content: .text(MCPTextContent(text: text)))
    }
    
    public static func assistant(_ text: String) -> MCPPromptMessage {
        MCPPromptMessage(role: "assistant", content: .text(MCPTextContent(text: text)))
    }
    
    public static func system(_ text: String) -> MCPPromptMessage {
        MCPPromptMessage(role: "system", content: .text(MCPTextContent(text: text)))
    }
}

// MARK: - Prompt Provider Protocol

public protocol MCPPromptProvider: Sendable {
    var definition: MCPPrompt { get }
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage]
}

// MARK: - Simple Prompt Implementation

public struct SimplePrompt: MCPPromptProvider {
    public let definition: MCPPrompt
    private let generator: @Sendable ([String: String]?) async throws -> [MCPPromptMessage]
    
    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        arguments: [MCPPromptArgument]? = nil,
        generator: @escaping @Sendable ([String: String]?) async throws -> [MCPPromptMessage]
    ) {
        self.definition = MCPPrompt(
            name: name,
            title: title,
            description: description,
            arguments: arguments
        )
        self.generator = generator
    }
    
    public nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        try await generator(arguments)
    }
}

// MARK: - Prompt Registry

public actor MCPPromptRegistry {
    private var prompts: [String: MCPPromptProvider] = [:]
    
    public init() {}
    
    public func register(_ prompt: MCPPromptProvider) {
        prompts[prompt.definition.name] = prompt
    }
    
    public func unregister(name: String) {
        prompts.removeValue(forKey: name)
    }
    
    public func get(name: String) -> MCPPromptProvider? {
        prompts[name]
    }
    
    public func list() -> [MCPPrompt] {
        prompts.values.map { $0.definition }
    }
    
    public func generate(name: String, arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        guard let prompt = prompts[name] else {
            throw JSONRPCError.methodNotFound(method: "prompts/get:\(name)")
        }
        return try await prompt.generate(arguments: arguments)
    }
}
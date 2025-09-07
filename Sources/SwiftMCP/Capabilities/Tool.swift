//
//  Tool.swift
//  SwiftMCP
//
//  Tool capability definitions
//

import Foundation

// MARK: - Tool Definition

public struct MCPTool: Codable, Hashable, @unchecked Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchema: [String: Any]?
    public let outputSchema: [String: Any]?
    public let annotations: MCPAnnotations?
    
    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: [String: Any]? = nil,
        outputSchema: [String: Any]? = nil,
        annotations: MCPAnnotations? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
    }
    
    // Hashable conformance
    public static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        lhs.name == rhs.name
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    // Codable conformance with custom implementation for [String: Any]
    enum CodingKeys: String, CodingKey {
        case name, title, description, inputSchema, outputSchema, annotations
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        annotations = try container.decodeIfPresent(MCPAnnotations.self, forKey: .annotations)
        
        if let schemaData = try container.decodeIfPresent(AnyCodable.self, forKey: .inputSchema) {
            inputSchema = schemaData.value as? [String: Any]
        } else {
            inputSchema = nil
        }
        
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
        try container.encodeIfPresent(annotations, forKey: .annotations)
        
        if let schema = inputSchema {
            try container.encode(AnyCodable(schema), forKey: .inputSchema)
        }
        
        if let schema = outputSchema {
            try container.encode(AnyCodable(schema), forKey: .outputSchema)
        }
    }
}

// MARK: - Tool Result

public struct MCPToolResult: Codable, Sendable {
    public let content: [MCPContent]?
    public let structuredContent: AnyCodable?
    public let isError: Bool?
    
    public init(
        content: [MCPContent]? = nil,
        structuredContent: AnyCodable? = nil,
        isError: Bool? = nil
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }
    
    public static func success(text: String) -> MCPToolResult {
        MCPToolResult(
            content: [.text(MCPTextContent(text: text))],
            isError: false
        )
    }
    
    public static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(
            content: [.text(MCPTextContent(text: message))],
            isError: true
        )
    }
}

// MARK: - Tool Executor Protocol

public protocol MCPToolExecutor: Sendable {
    var definition: MCPTool { get }
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult
}

// MARK: - Simple Tool Implementation

public struct SimpleTool: MCPToolExecutor {
    public let definition: MCPTool
    private let handler: @Sendable ([String: Any]?) async throws -> MCPToolResult
    
    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: [String: Any]? = nil,
        outputSchema: [String: Any]? = nil,
        handler: @escaping @Sendable ([String: Any]?) async throws -> MCPToolResult
    ) {
        self.definition = MCPTool(
            name: name,
            title: title,
            description: description,
            inputSchema: inputSchema,
            outputSchema: outputSchema
        )
        self.handler = handler
    }
    
    public nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        try await handler(arguments)
    }
}

// MARK: - Tool Registry

public actor MCPToolRegistry {
    private var tools: [String: MCPToolExecutor] = [:]
    
    public init() {}
    
    public func register(_ tool: MCPToolExecutor) {
        tools[tool.definition.name] = tool
    }
    
    public func unregister(name: String) {
        tools.removeValue(forKey: name)
    }
    
    public func get(name: String) -> MCPToolExecutor? {
        tools[name]
    }
    
    public func list() -> [MCPTool] {
        tools.values.map { $0.definition }
    }
    
    public nonisolated func execute(name: String, arguments: [String: Any]?) async throws -> MCPToolResult {
        let tool = await self.get(name: name)
        guard let tool = tool else {
            throw JSONRPCError.methodNotFound(method: "tools/call:\(name)")
        }
        return try await tool.execute(arguments: arguments)
    }
}
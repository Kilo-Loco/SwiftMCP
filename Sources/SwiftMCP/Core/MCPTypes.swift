//
//  MCPTypes.swift
//  SwiftMCP
//
//  Model Context Protocol Types
//

import Foundation

// MARK: - Protocol Version

public let MCPProtocolVersion = "2025-06-18"

// MARK: - Implementation Info

public struct MCPImplementationInfo: Codable, Sendable {
    public let name: String
    public let title: String?
    public let version: String
    
    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

// MARK: - Server Capabilities

public struct MCPServerCapabilities: Codable, Sendable {
    public let prompts: MCPPromptsCapability?
    public let resources: MCPResourcesCapability?
    public let tools: MCPToolsCapability?
    public let logging: MCPLoggingCapability?
    public let completions: MCPCompletionsCapability?
    public let experimental: [String: AnyCodable]?
    
    public init(
        prompts: MCPPromptsCapability? = nil,
        resources: MCPResourcesCapability? = nil,
        tools: MCPToolsCapability? = nil,
        logging: MCPLoggingCapability? = nil,
        completions: MCPCompletionsCapability? = nil,
        experimental: [String: AnyCodable]? = nil
    ) {
        self.prompts = prompts
        self.resources = resources
        self.tools = tools
        self.logging = logging
        self.completions = completions
        self.experimental = experimental
    }
}

public struct MCPPromptsCapability: Codable, Sendable {
    public let listChanged: Bool?
    
    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

public struct MCPResourcesCapability: Codable, Sendable {
    public let subscribe: Bool?
    public let listChanged: Bool?
    
    public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
        self.subscribe = subscribe
        self.listChanged = listChanged
    }
}

public struct MCPToolsCapability: Codable, Sendable {
    public let listChanged: Bool?
    
    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

public struct MCPLoggingCapability: Codable, Sendable {
    public init() {}
}

public struct MCPCompletionsCapability: Codable, Sendable {
    public init() {}
}

// MARK: - Client Capabilities

public struct MCPClientCapabilities: Codable, Sendable {
    public let roots: MCPRootsCapability?
    public let sampling: MCPSamplingCapability?
    public let elicitation: MCPElicitationCapability?
    public let experimental: [String: AnyCodable]?
    
    public init(
        roots: MCPRootsCapability? = nil,
        sampling: MCPSamplingCapability? = nil,
        elicitation: MCPElicitationCapability? = nil,
        experimental: [String: AnyCodable]? = nil
    ) {
        self.roots = roots
        self.sampling = sampling
        self.elicitation = elicitation
        self.experimental = experimental
    }
}

public struct MCPRootsCapability: Codable, Sendable {
    public let listChanged: Bool?
    
    public init(listChanged: Bool? = nil) {
        self.listChanged = listChanged
    }
}

public struct MCPSamplingCapability: Codable, Sendable {
    public init() {}
}

public struct MCPElicitationCapability: Codable, Sendable {
    public init() {}
}

// MARK: - Annotations

public struct MCPAnnotations: Codable, Hashable, Sendable {
    public let audience: [String]?
    public let priority: Double?
    public let lastModified: String?
    
    public init(audience: [String]? = nil, priority: Double? = nil, lastModified: String? = nil) {
        self.audience = audience
        self.priority = priority
        self.lastModified = lastModified
    }
}

// MARK: - Content Types

public enum MCPContent: Codable, Sendable {
    case text(MCPTextContent)
    case image(MCPImageContent)
    case audio(MCPAudioContent)
    case resource(MCPEmbeddedResource)
    case resourceLink(MCPResourceLink)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try MCPTextContent(from: decoder))
        case "image":
            self = .image(try MCPImageContent(from: decoder))
        case "audio":
            self = .audio(try MCPAudioContent(from: decoder))
        case "resource":
            self = .resource(try MCPEmbeddedResource(from: decoder))
        case "resource_link":
            self = .resourceLink(try MCPResourceLink(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .audio(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        case .resourceLink(let content):
            try content.encode(to: encoder)
        }
    }
}

public struct MCPTextContent: Codable, Sendable {
    public let type: String = "text"
    public let text: String
    public let annotations: MCPAnnotations?
    
    public init(text: String, annotations: MCPAnnotations? = nil) {
        self.text = text
        self.annotations = annotations
    }
}

public struct MCPImageContent: Codable, Sendable {
    public let type: String = "image"
    public let data: String
    public let mimeType: String
    public let annotations: MCPAnnotations?
    
    public init(data: String, mimeType: String, annotations: MCPAnnotations? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }
}

public struct MCPAudioContent: Codable, Sendable {
    public let type: String = "audio"
    public let data: String
    public let mimeType: String
    public let annotations: MCPAnnotations?
    
    public init(data: String, mimeType: String, annotations: MCPAnnotations? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }
}

public struct MCPEmbeddedResource: Codable, Sendable {
    public let type: String = "resource"
    public let resource: MCPResource
    
    public init(resource: MCPResource) {
        self.resource = resource
    }
}

public struct MCPResourceLink: Codable, Sendable {
    public let uri: String
    public let name: String?
    public let description: String?
    public let mimeType: String?
    public let annotations: MCPAnnotations?
    
    public init(
        uri: String,
        name: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        annotations: MCPAnnotations? = nil
    ) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
        self.annotations = annotations
    }
}

// MARK: - Resource

public struct MCPResource: Codable, Hashable, Sendable {
    public let uri: String
    public let title: String?
    public let description: String?
    public let mimeType: String?
    public let text: String?
    public let blob: String?
    public let annotations: MCPAnnotations?
    
    public init(
        uri: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        text: String? = nil,
        blob: String? = nil,
        annotations: MCPAnnotations? = nil
    ) {
        self.uri = uri
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
        self.annotations = annotations
    }
}
//
//  MCPServerBuilder.swift
//  SwiftMCP
//
//  Builder pattern for MCP Server
//

import Foundation

public class MCPServerBuilder {
    private let name: String
    private let version: String
    private var title: String?
    private var instructions: String?
    private var delegate: MCPServerDelegate?
    
    private var tools: [MCPToolExecutor] = []
    private var resources: [MCPResourceProvider] = []
    private var prompts: [MCPPromptProvider] = []
    
    private var enableTools = false
    private var enableResources = false
    private var enablePrompts = false
    private var enableLogging = false
    
    private var toolsListChanged = false
    private var resourcesListChanged = false
    private var resourcesSubscribe = false
    private var promptsListChanged = false
    
    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
    
    // MARK: - Server Info
    
    @discardableResult
    public func withTitle(_ title: String) -> Self {
        self.title = title
        return self
    }
    
    @discardableResult
    public func withInstructions(_ instructions: String) -> Self {
        self.instructions = instructions
        return self
    }
    
    @discardableResult
    public func withDelegate(_ delegate: MCPServerDelegate) -> Self {
        self.delegate = delegate
        return self
    }
    
    // MARK: - Tools
    
    @discardableResult
    public func withTool(_ tool: MCPToolExecutor) -> Self {
        tools.append(tool)
        enableTools = true
        return self
    }
    
    @discardableResult
    public func withTools(_ tools: [MCPToolExecutor]) -> Self {
        self.tools.append(contentsOf: tools)
        enableTools = true
        return self
    }
    
    @discardableResult
    public func withToolsListChanged(_ enabled: Bool = true) -> Self {
        toolsListChanged = enabled
        enableTools = true
        return self
    }
    
    // MARK: - Resources
    
    @discardableResult
    public func withResource(_ resource: MCPResourceProvider) -> Self {
        resources.append(resource)
        enableResources = true
        return self
    }
    
    @discardableResult
    public func withResources(_ resources: [MCPResourceProvider]) -> Self {
        self.resources.append(contentsOf: resources)
        enableResources = true
        return self
    }
    
    @discardableResult
    public func withResourcesListChanged(_ enabled: Bool = true) -> Self {
        resourcesListChanged = enabled
        enableResources = true
        return self
    }
    
    @discardableResult
    public func withResourcesSubscribe(_ enabled: Bool = true) -> Self {
        resourcesSubscribe = enabled
        enableResources = true
        return self
    }
    
    // MARK: - Prompts
    
    @discardableResult
    public func withPrompt(_ prompt: MCPPromptProvider) -> Self {
        prompts.append(prompt)
        enablePrompts = true
        return self
    }
    
    @discardableResult
    public func withPrompts(_ prompts: [MCPPromptProvider]) -> Self {
        self.prompts.append(contentsOf: prompts)
        enablePrompts = true
        return self
    }
    
    @discardableResult
    public func withPromptsListChanged(_ enabled: Bool = true) -> Self {
        promptsListChanged = enabled
        enablePrompts = true
        return self
    }
    
    // MARK: - Other Capabilities
    
    @discardableResult
    public func withLogging(_ enabled: Bool = true) -> Self {
        enableLogging = enabled
        return self
    }
    
    // MARK: - Build
    
    public func build() async -> MCPServer {
        // Build capabilities
        let capabilities = MCPServerCapabilities(
            prompts: enablePrompts ? MCPPromptsCapability(listChanged: promptsListChanged) : nil,
            resources: enableResources ? MCPResourcesCapability(
                subscribe: resourcesSubscribe,
                listChanged: resourcesListChanged
            ) : nil,
            tools: enableTools ? MCPToolsCapability(listChanged: toolsListChanged) : nil,
            logging: enableLogging ? MCPLoggingCapability() : nil
        )
        
        // Create server
        let server = MCPServer(
            name: name,
            version: version,
            title: title,
            instructions: instructions,
            capabilities: capabilities
        )
        
        // Set delegate if provided
        if let delegate = delegate {
            await server.setDelegate(delegate)
        }
        
        // Register capabilities
        for tool in tools {
            await server.registerTool(tool)
        }
        
        for resource in resources {
            await server.registerResource(resource)
        }
        
        for prompt in prompts {
            await server.registerPrompt(prompt)
        }
        
        return server
    }
}
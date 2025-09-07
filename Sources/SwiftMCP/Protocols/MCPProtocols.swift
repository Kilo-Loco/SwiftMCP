//
//  MCPProtocols.swift
//  SwiftMCP
//
//  Protocol definitions for better testability and flexibility
//

import Foundation

// MARK: - Server Protocol

/// Protocol defining the core MCP server functionality
public protocol MCPServerProtocol: Actor {
    /// The server's current state
    var currentState: MCPServerState { get async }
    
    /// Server information
    var serverInfo: MCPImplementationInfo { get async }
    
    /// Server capabilities
    var serverCapabilities: MCPServerCapabilities { get async }
    
    /// Start the server with a transport
    func start(transport: MCPTransport) async throws
    
    /// Shutdown the server gracefully
    func shutdown() async
    
    /// Handle an incoming message
    func handleMessage(_ data: Data) async -> Data?
    
    /// Set the server delegate
    func setDelegate(_ delegate: MCPServerDelegate?) async
    
    /// Register a tool
    func registerTool(_ tool: MCPToolExecutor) async
    
    /// Register a resource
    func registerResource(_ resource: MCPResourceProvider) async
    
    /// Register a prompt
    func registerPrompt(_ prompt: MCPPromptProvider) async
    
    /// Get all registered tools
    func getRegisteredTools() async -> [MCPTool]
    
    /// Get all registered resources
    func getRegisteredResources() async -> [MCPResource]
    
    /// Get all registered prompts
    func getRegisteredPrompts() async -> [MCPPrompt]
}

// MARK: - Tool Protocol

/// Protocol for tool execution
public protocol MCPToolProtocol: Sendable {
    /// The tool's definition
    var definition: MCPTool { get }
    
    /// Execute the tool with arguments
    func execute(arguments: [String: Any]?) async throws -> MCPToolResult
}

// MARK: - Resource Protocol

/// Protocol for resource providers
public protocol MCPResourceProtocol: Sendable {
    /// The resource definition
    var definition: MCPResource { get async }
    
    /// Read the resource
    func read() async throws -> MCPResource
    
    /// Subscribe to resource updates
    func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws
    
    /// Unsubscribe from updates
    func unsubscribe() async
}

// MARK: - Prompt Protocol

/// Protocol for prompt providers
public protocol MCPPromptProtocol: Sendable {
    /// The prompt definition
    var definition: MCPPrompt { get }
    
    /// Generate prompt messages
    func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage]
}

// MARK: - Transport Protocol Extension

/// Extended transport protocol with more functionality
public protocol MCPTransportProtocol: MCPTransport {
    /// Check if transport is connected
    var isConnected: Bool { get async }
    
    /// Get transport statistics
    func getStatistics() async -> TransportStatistics
}

/// Transport statistics
public struct TransportStatistics: Sendable {
    public let bytesSent: Int
    public let bytesReceived: Int
    public let messagesSent: Int
    public let messagesReceived: Int
    public let connectedAt: Date?
    public let lastActivityAt: Date?
    
    public init(
        bytesSent: Int = 0,
        bytesReceived: Int = 0,
        messagesSent: Int = 0,
        messagesReceived: Int = 0,
        connectedAt: Date? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.connectedAt = connectedAt
        self.lastActivityAt = lastActivityAt
    }
}

// MARK: - Conformance

// Make existing types conform to protocols
extension MCPServer: MCPServerProtocol {}
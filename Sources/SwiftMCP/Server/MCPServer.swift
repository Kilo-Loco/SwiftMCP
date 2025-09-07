//
//  MCPServer.swift
//  SwiftMCP
//
//  Core MCP Server implementation
//

import Foundation
import os.log

// MARK: - Server Delegate

public protocol MCPServerDelegate: AnyObject, Sendable {
    func server(_ server: MCPServer, didReceiveRequest request: JSONRPCRequest) async -> Result<AnyCodable, JSONRPCError>
    func server(_ server: MCPServer, didReceiveNotification notification: JSONRPCNotification) async
    func serverDidInitialize(_ server: MCPServer) async
    func serverWillShutdown(_ server: MCPServer) async
}

// MARK: - Server State

public enum MCPServerState: Sendable {
    case uninitialized
    case initializing
    case ready
    case shuttingDown
    case terminated
}

// MARK: - MCP Server

public actor MCPServer {
    private let logger = Logger(subsystem: "SwiftMCP", category: "Server")
    
    // Server info
    public let serverInfo: MCPImplementationInfo
    public let serverCapabilities: MCPServerCapabilities
    public let instructions: String?
    
    // State
    private var state: MCPServerState = .uninitialized
    private var clientInfo: MCPImplementationInfo?
    private var clientCapabilities: MCPClientCapabilities?
    
    // Registries
    private let toolRegistry: MCPToolRegistry
    private let resourceRegistry: MCPResourceRegistry
    private let promptRegistry: MCPPromptRegistry
    
    // Delegate
    public weak var delegate: MCPServerDelegate?
    
    // Transport
    private var transport: MCPTransport?
    
    // MARK: - Initialization
    
    public init(
        name: String,
        version: String,
        title: String? = nil,
        instructions: String? = nil,
        capabilities: MCPServerCapabilities? = nil
    ) {
        self.serverInfo = MCPImplementationInfo(
            name: name,
            title: title,
            version: version
        )
        self.instructions = instructions
        self.serverCapabilities = capabilities ?? MCPServerCapabilities()
        
        self.toolRegistry = MCPToolRegistry()
        self.resourceRegistry = MCPResourceRegistry()
        self.promptRegistry = MCPPromptRegistry()
    }
    
    // MARK: - Builder Pattern
    
    public static func builder(name: String, version: String) -> MCPServerBuilder {
        MCPServerBuilder(name: name, version: version)
    }
    
    // MARK: - Lifecycle
    
    public func start(transport: MCPTransport) async throws {
        guard state == .uninitialized else {
            throw MCPError.invalidState("Server already started")
        }
        
        self.transport = transport
        state = .initializing
        
        try await transport.start()
        
        // Start message processing loop
        Task {
            await processMessages()
        }
    }
    
    public func shutdown() async {
        guard state == .ready else { return }
        
        state = .shuttingDown
        await delegate?.serverWillShutdown(self)
        
        await transport?.stop()
        state = .terminated
    }
    
    // MARK: - Message Processing
    
    private func processMessages() async {
        guard let transport = transport else { return }
        
        do {
            while state != .terminated {
                let data = try await transport.receive()
                await handleMessage(data)
            }
        } catch {
            logger.error("Message processing error: \(error)")
        }
    }
    
    private func handleMessage(_ data: Data) async {
        do {
            // Try to decode as request
            if let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) {
                let response = await handleRequest(request)
                let responseData = try JSONEncoder().encode(response)
                try await transport?.send(responseData)
            }
            // Try to decode as notification
            else if let notification = try? JSONDecoder().decode(JSONRPCNotification.self, from: data) {
                await handleNotification(notification)
            }
            else {
                logger.error("Invalid message format")
            }
        } catch {
            logger.error("Message handling error: \(error)")
        }
    }
    
    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        // Check initialization
        if request.method != "initialize" && state != .ready {
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(code: -32002, message: "Server not initialized")
            )
        }
        
        // Route request
        do {
            let result = try await routeRequest(request)
            return JSONRPCResponse(id: request.id, result: result)
        } catch let error as JSONRPCError {
            return JSONRPCResponse(id: request.id, error: error)
        } catch {
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError.internalError(data: AnyCodable(error.localizedDescription))
            )
        }
    }
    
    private func routeRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        switch request.method {
        case "initialize":
            return try await handleInitialize(request.params)
            
        case "tools/list":
            return try await handleToolsList(request.params)
        case "tools/call":
            return try await handleToolCall(request.params)
            
        case "resources/list":
            return try await handleResourcesList(request.params)
        case "resources/read":
            return try await handleResourceRead(request.params)
            
        case "prompts/list":
            return try await handlePromptsList(request.params)
        case "prompts/get":
            return try await handlePromptGet(request.params)
            
        default:
            // Check delegate
            if let delegate = delegate {
                let result = await delegate.server(self, didReceiveRequest: request)
                switch result {
                case .success(let value):
                    return value
                case .failure(let error):
                    throw error
                }
            }
            throw JSONRPCError.methodNotFound(method: request.method)
        }
    }
    
    private func handleNotification(_ notification: JSONRPCNotification) async {
        switch notification.method {
        case "notifications/initialized":
            state = .ready
            await delegate?.serverDidInitialize(self)
            
        default:
            await delegate?.server(self, didReceiveNotification: notification)
        }
    }
    
    // MARK: - Protocol Handlers
    
    private func handleInitialize(_ params: AnyCodable?) async throws -> AnyCodable {
        guard let paramsDict = params?.value as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: paramsDict) else {
            throw JSONRPCError.invalidParams()
        }
        
        struct InitializeRequest: Codable {
            let protocolVersion: String
            let capabilities: MCPClientCapabilities
            let clientInfo: MCPImplementationInfo
        }
        
        let request = try JSONDecoder().decode(InitializeRequest.self, from: data)
        
        // Store client info
        self.clientInfo = request.clientInfo
        self.clientCapabilities = request.capabilities
        
        // Create response
        let response = [
            "protocolVersion": MCPProtocolVersion,
            "capabilities": try JSONEncoder().encode(serverCapabilities).jsonObject(),
            "serverInfo": try JSONEncoder().encode(serverInfo).jsonObject(),
            "instructions": instructions as Any
        ]
        
        return AnyCodable(response)
    }
    
    private func handleToolsList(_ params: AnyCodable?) async throws -> AnyCodable {
        let tools = await toolRegistry.list()
        let response = ["tools": tools.map { $0.encode() }]
        return AnyCodable(response)
    }
    
    private func handleToolCall(_ params: AnyCodable?) async throws -> AnyCodable {
        guard let paramsDict = params?.value as? [String: Any],
              let name = paramsDict["name"] as? String else {
            throw JSONRPCError.invalidParams()
        }
        
        let arguments = paramsDict["arguments"] as? [String: Any]
        let result = try await toolRegistry.execute(name: name, arguments: arguments)
        
        return AnyCodable(try JSONEncoder().encode(result).jsonObject())
    }
    
    private func handleResourcesList(_ params: AnyCodable?) async throws -> AnyCodable {
        let resources = await resourceRegistry.list()
        let response = ["resources": resources.map { $0.encode() }]
        return AnyCodable(response)
    }
    
    private func handleResourceRead(_ params: AnyCodable?) async throws -> AnyCodable {
        guard let paramsDict = params?.value as? [String: Any],
              let uri = paramsDict["uri"] as? String else {
            throw JSONRPCError.invalidParams()
        }
        
        let resource = try await resourceRegistry.read(uri: uri)
        return AnyCodable(resource.encode())
    }
    
    private func handlePromptsList(_ params: AnyCodable?) async throws -> AnyCodable {
        let prompts = await promptRegistry.list()
        let response = ["prompts": prompts.map { $0.encode() }]
        return AnyCodable(response)
    }
    
    private func handlePromptGet(_ params: AnyCodable?) async throws -> AnyCodable {
        guard let paramsDict = params?.value as? [String: Any],
              let name = paramsDict["name"] as? String else {
            throw JSONRPCError.invalidParams()
        }
        
        let arguments = paramsDict["arguments"] as? [String: String]
        let messages = try await promptRegistry.generate(name: name, arguments: arguments)
        
        let response = ["messages": messages.map { $0.encode() }]
        return AnyCodable(response)
    }
    
    // MARK: - Registration Methods
    
    public func registerTool(_ tool: MCPToolExecutor) async {
        await toolRegistry.register(tool)
    }
    
    public func registerResource(_ resource: MCPResourceProvider) async {
        await resourceRegistry.register(resource)
    }
    
    public func registerPrompt(_ prompt: MCPPromptProvider) async {
        await promptRegistry.register(prompt)
    }
}

// MARK: - Extensions for Encoding

private extension Encodable {
    func encode() -> [String: Any] {
        (try? JSONEncoder().encode(self).jsonObject() as? [String: Any]) ?? [:]
    }
}

private extension Data {
    func jsonObject() -> Any {
        (try? JSONSerialization.jsonObject(with: self)) ?? [:]
    }
}

// MARK: - MCP Error

public enum MCPError: LocalizedError {
    case invalidState(String)
    case transportError(Error)
    case encodingError(Error)
    case decodingError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .transportError(let error):
            return "Transport error: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Encoding error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
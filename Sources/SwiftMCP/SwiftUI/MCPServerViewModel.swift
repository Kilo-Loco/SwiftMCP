//
//  MCPServerViewModel.swift
//  SwiftMCP
//
//  SwiftUI integration for MCP servers
//

#if canImport(SwiftUI)
import SwiftUI
import Combine

/// Observable view model for MCP server
@MainActor
public final class MCPServerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isRunning = false
    @Published public private(set) var state: MCPServerState = .uninitialized
    @Published public private(set) var tools: [MCPTool] = []
    @Published public private(set) var resources: [MCPResource] = []
    @Published public private(set) var prompts: [MCPPrompt] = []
    @Published public private(set) var lastError: MCPError?
    @Published public private(set) var isLoading = false
    @Published public private(set) var statusMessage = "Not initialized"
    
    // MARK: - Private Properties
    
    private let server: MCPServerProtocol
    private var updateTask: Task<Void, Never>?
    private let updateInterval: TimeInterval
    
    // MARK: - Statistics
    
    @Published public private(set) var requestCount = 0
    @Published public private(set) var errorCount = 0
    @Published public private(set) var uptime: TimeInterval = 0
    private var startTime: Date?
    
    // MARK: - Initialization
    
    public init(server: MCPServerProtocol, updateInterval: TimeInterval = 1.0) {
        self.server = server
        self.updateInterval = updateInterval
        
        Task {
            await startObserving()
        }
    }
    
    deinit {
        updateTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Start the server
    public func start(transport: MCPTransport) async {
        isLoading = true
        lastError = nil
        
        do {
            try await server.start(transport: transport)
            startTime = Date()
            statusMessage = "Server running"
        } catch {
            lastError = error as? MCPError ?? .internalError(error.localizedDescription)
            statusMessage = "Failed to start: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Shutdown the server
    public func shutdown() async {
        isLoading = true
        
        await server.shutdown()
        startTime = nil
        statusMessage = "Server stopped"
        
        isLoading = false
    }
    
    /// Register a tool
    public func registerTool(_ tool: MCPToolExecutor) async {
        await server.registerTool(tool)
        await updateTools()
    }
    
    /// Register a resource
    public func registerResource(_ resource: MCPResourceProvider) async {
        await server.registerResource(resource)
        await updateResources()
    }
    
    /// Register a prompt
    public func registerPrompt(_ prompt: MCPPromptProvider) async {
        await server.registerPrompt(prompt)
        await updatePrompts()
    }
    
    /// Execute a tool
    public func executeTool(name: String, arguments: [String: Any]? = nil) async -> MCPResult<MCPToolResult> {
        requestCount += 1
        
        // This would need to be added to the protocol
        // For now, return an error
        return .failure(.toolNotFound(name: name))
    }
    
    /// Clear the last error
    public func clearError() {
        lastError = nil
    }
    
    // MARK: - Private Methods
    
    private func startObserving() async {
        updateTask = Task {
            while !Task.isCancelled {
                await updateState()
                
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
        }
        
        // Initial update
        await updateState()
    }
    
    private func updateState() async {
        let newState = await server.currentState
        
        if state != newState {
            state = newState
            isRunning = state == .ready
            
            statusMessage = statusDescription(for: state)
        }
        
        await updateTools()
        await updateResources()
        await updatePrompts()
        
        // Update uptime
        if let startTime = startTime {
            uptime = Date().timeIntervalSince(startTime)
        }
    }
    
    private func updateTools() async {
        tools = await server.getRegisteredTools()
    }
    
    private func updateResources() async {
        resources = await server.getRegisteredResources()
    }
    
    private func updatePrompts() async {
        prompts = await server.getRegisteredPrompts()
    }
    
    private func statusDescription(for state: MCPServerState) -> String {
        switch state {
        case .uninitialized:
            return "Not initialized"
        case .initializing:
            return "Initializing..."
        case .ready:
            return "Ready"
        case .shuttingDown:
            return "Shutting down..."
        case .terminated:
            return "Terminated"
        }
    }
}

// MARK: - Tool Execution View Model

/// View model for executing a specific tool
@MainActor
public final class MCPToolExecutionViewModel: ObservableObject {
    
    @Published public var tool: MCPTool
    @Published public var arguments: [String: String] = [:]
    @Published public var isExecuting = false
    @Published public var result: MCPToolResult?
    @Published public var error: Error?
    
    private let serverViewModel: MCPServerViewModel
    
    public init(tool: MCPTool, serverViewModel: MCPServerViewModel) {
        self.tool = tool
        self.serverViewModel = serverViewModel
        
        // Initialize arguments from schema
        if let schema = tool.inputSchema,
           let properties = schema["properties"] as? [String: Any] {
            for (key, _) in properties {
                arguments[key] = ""
            }
        }
    }
    
    public func execute() async {
        isExecuting = true
        error = nil
        result = nil
        
        let result = await serverViewModel.executeTool(
            name: tool.name,
            arguments: arguments.isEmpty ? nil : arguments
        )
        
        switch result {
        case .success(let toolResult):
            self.result = toolResult
        case .failure(let err):
            self.error = err
        }
        
        isExecuting = false
    }
    
    public func reset() {
        result = nil
        error = nil
        arguments.removeAll()
    }
}

// MARK: - Connection Status

/// Observable connection status
@MainActor
public final class MCPConnectionStatus: ObservableObject {
    public enum Status {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        public var color: Color {
            switch self {
            case .disconnected: return .gray
            case .connecting: return .orange
            case .connected: return .green
            case .error: return .red
            }
        }
        
        public var symbol: String {
            switch self {
            case .disconnected: return "wifi.slash"
            case .connecting: return "wifi.exclamationmark"
            case .connected: return "wifi"
            case .error: return "wifi.slash"
            }
        }
    }
    
    @Published public var status: Status = .disconnected
    @Published public var lastActivity: Date?
    @Published public var bytesReceived: Int = 0
    @Published public var bytesSent: Int = 0
    
    public init() {}
    
    public func updateStatus(_ newStatus: Status) {
        status = newStatus
        lastActivity = Date()
    }
    
    public func recordActivity(sent: Int = 0, received: Int = 0) {
        bytesSent += sent
        bytesReceived += received
        lastActivity = Date()
    }
    
    public func reset() {
        status = .disconnected
        lastActivity = nil
        bytesReceived = 0
        bytesSent = 0
    }
}
#endif
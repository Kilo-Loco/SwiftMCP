//
//  ServerLifecycleManagement.swift
//  SwiftMCP Examples
//
//  Demonstrates complete server lifecycle management with the new APIs
//  Shows initialization, runtime management, and graceful shutdown patterns
//

import Foundation
import SwiftMCP
import SwiftMCPTransports
import os.log

// MARK: - Lifecycle Manager

/// ServerLifecycleManager handles complete server lifecycle
actor ServerLifecycleManager {
    enum State {
        case idle
        case initializing
        case running
        case shuttingDown
        case terminated
    }
    
    private var state: State = .idle
    private var server: MCPServer?
    private var transport: MCPTransport?
    private let logger = Logger(subsystem: "ServerLifecycle", category: "Manager")
    
    // Metrics
    private var startTime: Date?
    private var initializationTime: TimeInterval?
    private var requestsHandled = 0
    private var errors = 0
    
    /// Initialize server with configuration
    func initializeServer(
        name: String,
        version: String,
        delegate: MCPServerDelegate? = nil
    ) async throws -> MCPServer {
        guard state == .idle else {
            throw LifecycleError.invalidState("Cannot initialize in state: \(state)")
        }
        
        state = .initializing
        let initStart = Date()
        
        logger.info("Initializing server: \(name) v\(version)")
        
        // Create server using factory method
        let server = await MCPServer.create(
            name: name,
            version: version,
            title: "\(name) Server",
            instructions: "Managed server with lifecycle support",
            delegate: delegate
        )
        
        self.server = server
        
        // Register capabilities
        await registerCapabilities(on: server)
        
        initializationTime = Date().timeIntervalSince(initStart)
        logger.info("Server initialized in \(self.initializationTime ?? 0) seconds")
        
        return server
    }
    
    /// Start server with specified transport
    func startServer(with transport: MCPTransport) async throws {
        guard state == .initializing,
              let server = server else {
            throw LifecycleError.invalidState("Server not initialized")
        }
        
        self.transport = transport
        
        logger.info("Starting server with transport: \(type(of: transport))")
        
        // For custom transports, we might not use server.start()
        // Instead, we manually manage the connection
        if transport is StdioTransport {
            let stdioTransport = transport as! StdioTransport
            await stdioTransport.setDelegate(TransportHandler(server: server, manager: self))
        }
        
        try await transport.start()
        
        state = .running
        startTime = Date()
        
        logger.info("Server started successfully")
    }
    
    /// Perform health check
    func healthCheck() async -> HealthStatus {
        guard state == .running else {
            return HealthStatus(
                healthy: false,
                state: String(describing: state),
                uptime: 0,
                metrics: nil
            )
        }
        
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return HealthStatus(
            healthy: true,
            state: "running",
            uptime: uptime,
            metrics: HealthMetrics(
                requestsHandled: requestsHandled,
                errors: errors,
                averageRequestsPerSecond: Double(requestsHandled) / max(uptime, 1)
            )
        )
    }
    
    /// Graceful shutdown with timeout
    func shutdown(timeout: TimeInterval = 30) async throws {
        guard state == .running else {
            logger.warning("Shutdown called in state: \(self.state)")
            return
        }
        
        state = .shuttingDown
        logger.info("Starting graceful shutdown (timeout: \(timeout)s)")
        
        // Create shutdown task with timeout
        let shutdownTask = Task {
            // Stop accepting new requests
            await transport?.stop()
            
            // Wait for pending operations
            try await Task.sleep(nanoseconds: UInt64(1_000_000_000))
            
            // Shutdown server
            await server?.shutdown()
            
            state = .terminated
            logger.info("Shutdown completed")
        }
        
        // Wait with timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw LifecycleError.shutdownTimeout
        }
        
        do {
            // Race between shutdown and timeout
            _ = try await Task.select(shutdownTask, timeoutTask)
            timeoutTask.cancel()
        } catch LifecycleError.shutdownTimeout {
            logger.error("Shutdown timeout - forcing termination")
            shutdownTask.cancel()
            state = .terminated
            throw LifecycleError.shutdownTimeout
        }
        
        logFinalStats()
    }
    
    /// Emergency stop without cleanup
    func emergencyStop() async {
        logger.critical("Emergency stop initiated")
        
        await transport?.stop()
        await server?.shutdown()
        state = .terminated
        
        logger.critical("Emergency stop completed")
    }
    
    func incrementRequestCount() {
        requestsHandled += 1
    }
    
    func incrementErrorCount() {
        errors += 1
    }
    
    private func registerCapabilities(on server: MCPServer) async {
        // Register standard tools
        await server.registerTool(SimpleTool(
            name: "health",
            title: "Health Check",
            handler: { _ in
                let status = await self.healthCheck()
                return MCPToolResult.success(text: """
                    Health: \(status.healthy ? "✅" : "❌")
                    State: \(status.state)
                    Uptime: \(String(format: "%.2f", status.uptime)) seconds
                    Requests: \(status.metrics?.requestsHandled ?? 0)
                    """)
            }
        ))
        
        await server.registerTool(SimpleTool(
            name: "shutdown",
            title: "Graceful Shutdown",
            handler: { arguments in
                let timeout = (arguments?["timeout"] as? Double) ?? 30
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Delay 1 second
                    try? await self.shutdown(timeout: timeout)
                }
                return MCPToolResult.success(text: "Shutdown initiated")
            }
        ))
    }
    
    private func logFinalStats() {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        logger.info("""
        === Server Statistics ===
        Uptime: \(String(format: "%.2f", uptime)) seconds
        Initialization time: \(String(format: "%.3f", initializationTime ?? 0)) seconds
        Requests handled: \(requestsHandled)
        Errors: \(errors)
        Average RPS: \(String(format: "%.2f", Double(requestsHandled) / max(uptime, 1)))
        """)
    }
}

// MARK: - Transport Handler

class TransportHandler: StdioTransportDelegate {
    private let server: MCPServer
    private weak var manager: ServerLifecycleManager?
    
    init(server: MCPServer, manager: ServerLifecycleManager) {
        self.server = server
        self.manager = manager
    }
    
    func transport(_ transport: StdioTransport, didReceive data: Data) async {
        await manager?.incrementRequestCount()
        
        if let response = await server.handleMessage(data) {
            do {
                try await transport.send(response)
            } catch {
                await manager?.incrementErrorCount()
            }
        }
    }
    
    func transportDidConnect(_ transport: StdioTransport) async {
        print("Transport connected")
    }
    
    func transportDidDisconnect(_ transport: StdioTransport) async {
        print("Transport disconnected")
    }
    
    func transport(_ transport: StdioTransport, didEncounterError error: Error) async {
        await manager?.incrementErrorCount()
        print("Transport error: \(error)")
    }
}

// MARK: - Supporting Types

struct HealthStatus {
    let healthy: Bool
    let state: String
    let uptime: TimeInterval
    let metrics: HealthMetrics?
}

struct HealthMetrics {
    let requestsHandled: Int
    let errors: Int
    let averageRequestsPerSecond: Double
}

enum LifecycleError: LocalizedError {
    case invalidState(String)
    case shutdownTimeout
    case initializationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .shutdownTimeout:
            return "Shutdown timeout exceeded"
        case .initializationFailed(let reason):
            return "Initialization failed: \(reason)"
        }
    }
}

// MARK: - Advanced Lifecycle Delegate

/// AdvancedServerDelegate demonstrates sophisticated lifecycle handling
class AdvancedServerDelegate: MCPServerDelegate {
    private let manager: ServerLifecycleManager
    private var initTime: Date?
    
    init(manager: ServerLifecycleManager) {
        self.manager = manager
    }
    
    func server(_ server: MCPServer, didReceiveRequest request: JSONRPCRequest) async -> Result<AnyCodable, JSONRPCError> {
        // Track all requests
        await manager.incrementRequestCount()
        
        // Handle system requests
        switch request.method {
        case "system/health":
            let health = await manager.healthCheck()
            return .success(AnyCodable([
                "healthy": health.healthy,
                "uptime": health.uptime,
                "metrics": [
                    "requests": health.metrics?.requestsHandled ?? 0,
                    "errors": health.metrics?.errors ?? 0,
                    "rps": health.metrics?.averageRequestsPerSecond ?? 0
                ]
            ]))
            
        case "system/restart":
            Task {
                // Graceful restart
                try? await manager.shutdown()
                // In production, would trigger restart mechanism
            }
            return .success(AnyCodable(["status": "restarting"]))
            
        default:
            return .failure(JSONRPCError.methodNotFound(method: request.method))
        }
    }
    
    func server(_ server: MCPServer, didReceiveNotification notification: JSONRPCNotification) async {
        print("📨 Notification: \(notification.method)")
    }
    
    func serverDidInitialize(_ server: MCPServer) async {
        initTime = Date()
        print("✅ Server initialized at \(initTime!.ISO8601Format())")
        
        // Perform post-init tasks
        await performPostInitialization(server: server)
    }
    
    func serverWillShutdown(_ server: MCPServer) async {
        let runtime = initTime.map { Date().timeIntervalSince($0) } ?? 0
        print("🛑 Server shutting down after \(String(format: "%.2f", runtime)) seconds")
        
        // Perform pre-shutdown tasks
        await performPreShutdown(server: server)
    }
    
    private func performPostInitialization(server: MCPServer) async {
        // Register runtime tools based on environment
        if ProcessInfo.processInfo.environment["DEBUG"] != nil {
            await server.registerTool(SimpleTool(
                name: "debug_info",
                title: "Debug Information",
                handler: { _ in
                    MCPToolResult.success(text: "Debug mode active")
                }
            ))
        }
    }
    
    private func performPreShutdown(server: MCPServer) async {
        // Save state, flush logs, etc.
        print("💾 Saving server state...")
        // Implementation here
    }
}

// MARK: - Usage Examples

struct LifecycleExamples {
    /// Basic lifecycle management
    static func basicLifecycle() async throws {
        print("=== Basic Server Lifecycle ===\n")
        
        let manager = ServerLifecycleManager()
        
        // 1. Initialize
        let server = try await manager.initializeServer(
            name: "basic-server",
            version: "1.0.0"
        )
        
        // 2. Start
        let transport = StdioTransport()
        try await manager.startServer(with: transport)
        
        // 3. Run for a while
        print("Server running... (10 seconds)")
        try await Task.sleep(nanoseconds: 10_000_000_000)
        
        // 4. Health check
        let health = await manager.healthCheck()
        print("Health check: \(health.healthy ? "Healthy" : "Unhealthy")")
        
        // 5. Graceful shutdown
        try await manager.shutdown(timeout: 5)
        
        print("\n✅ Basic lifecycle completed")
    }
    
    /// Advanced lifecycle with delegate
    static func advancedLifecycle() async throws {
        print("=== Advanced Server Lifecycle ===\n")
        
        let manager = ServerLifecycleManager()
        let delegate = AdvancedServerDelegate(manager: manager)
        
        // Initialize with delegate
        let server = try await manager.initializeServer(
            name: "advanced-server",
            version: "2.0.0",
            delegate: delegate
        )
        
        // Start with custom transport
        let transport = StdioTransport()
        try await manager.startServer(with: transport)
        
        // Simulate runtime operations
        print("Simulating operations...")
        
        // Send test messages
        let testMessages = [
            """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
            """,
            """
            {"jsonrpc":"2.0","method":"notifications/initialized"}
            """,
            """
            {"jsonrpc":"2.0","id":2,"method":"system/health"}
            """,
            """
            {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health"}}
            """
        ]
        
        for message in testMessages {
            if let data = message.data(using: .utf8) {
                _ = await server.handleMessage(data)
                await manager.incrementRequestCount()
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        
        // Check health
        let health = await manager.healthCheck()
        print("\nFinal health status:")
        print("  Healthy: \(health.healthy)")
        print("  Uptime: \(String(format: "%.2f", health.uptime))s")
        print("  Requests: \(health.metrics?.requestsHandled ?? 0)")
        
        // Graceful shutdown
        try await manager.shutdown(timeout: 10)
        
        print("\n✅ Advanced lifecycle completed")
    }
    
    /// Error recovery example
    static func errorRecovery() async throws {
        print("=== Error Recovery Lifecycle ===\n")
        
        let manager = ServerLifecycleManager()
        
        do {
            // Initialize server
            _ = try await manager.initializeServer(
                name: "recovery-server",
                version: "1.0.0"
            )
            
            // Simulate error condition
            print("Simulating error condition...")
            
            // Emergency stop
            await manager.emergencyStop()
            
            print("Emergency stop completed")
            
        } catch {
            print("Error occurred: \(error)")
            // In production, implement recovery logic
        }
        
        print("\n✅ Error recovery completed")
    }
}

// MARK: - Main Entry Point

@main
struct ServerLifecycleManagementExample {
    static func main() async throws {
        let example = CommandLine.arguments.dropFirst().first ?? "basic"
        
        do {
            switch example {
            case "basic":
                try await LifecycleExamples.basicLifecycle()
                
            case "advanced":
                try await LifecycleExamples.advancedLifecycle()
                
            case "recovery":
                try await LifecycleExamples.errorRecovery()
                
            default:
                print("""
                Usage: ServerLifecycleManagement [example]
                
                Examples:
                  basic    - Basic lifecycle management
                  advanced - Advanced with delegate and metrics
                  recovery - Error recovery demonstration
                """)
            }
        } catch {
            print("Fatal error: \(error)")
            exit(1)
        }
    }
}

// MARK: - Key Concepts

/*
 This example demonstrates:
 
 1. **Complete Lifecycle Management**
    - Initialization with `MCPServer.create()`
    - Runtime management with health checks
    - Graceful shutdown with `server.shutdown()`
    - Emergency stop procedures
 
 2. **State Management**
    - Track server state transitions
    - Validate operations based on state
    - Handle invalid state errors
 
 3. **Metrics and Monitoring**
    - Request counting
    - Error tracking
    - Performance metrics (RPS)
    - Health checks
 
 4. **Graceful Shutdown**
    - Stop accepting new requests
    - Wait for pending operations
    - Timeout handling
    - Cleanup procedures
 
 5. **Error Recovery**
    - Emergency stop
    - Error isolation
    - Recovery strategies
 
 Key APIs used:
 - `MCPServer.create()` - Factory method
 - `MCPServer.setDelegate()` - Set lifecycle delegate
 - `MCPServer.handleMessage()` - Process messages
 - `MCPServer.shutdown()` - Graceful shutdown
 - `MCPServerDelegate` - Lifecycle callbacks
 - `StdioTransport.setDelegate()` - Transport events
 */
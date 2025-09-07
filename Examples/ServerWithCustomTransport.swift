//
//  ServerWithCustomTransport.swift
//  SwiftMCP Examples
//
//  Demonstrates using MCPServer with the new public APIs for custom transport implementations
//  Shows handleMessage(), shutdown(), and delegate patterns
//

import Foundation
import SwiftMCP
import SwiftMCPTransports

// MARK: - Custom Transport Example

/// CustomWebSocketTransport demonstrates how to implement a custom transport
/// using the new public MCPServer APIs
class CustomWebSocketTransport: MCPTransport {
    private var server: MCPServer?
    private var isConnected = false
    
    // Simulated WebSocket connection
    private var messageQueue: [Data] = []
    
    func setServer(_ server: MCPServer) {
        self.server = server
    }
    
    func start() async throws {
        isConnected = true
        print("WebSocket transport connected")
        
        // Start processing incoming messages
        Task {
            await processIncomingMessages()
        }
    }
    
    func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPTransportError.notConnected
        }
        
        // In real implementation, send via WebSocket
        if let string = String(data: data, encoding: .utf8) {
            print("Sending via WebSocket: \(string.prefix(100))...")
        }
    }
    
    func receive() async throws -> Data {
        // This would normally wait for WebSocket messages
        // For demo, we'll just wait
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return Data()
    }
    
    func stop() async {
        isConnected = false
        print("WebSocket transport disconnected")
    }
    
    // Simulate receiving messages from WebSocket
    private func processIncomingMessages() async {
        while isConnected {
            // In real implementation, this would be WebSocket message handler
            if !messageQueue.isEmpty {
                let message = messageQueue.removeFirst()
                
                // Use the new public handleMessage API
                if let response = await server?.handleMessage(message) {
                    // Send response back through WebSocket
                    try? await send(response)
                }
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
    
    // Simulate receiving a message from client
    func simulateIncomingMessage(_ json: String) {
        if let data = json.data(using: .utf8) {
            messageQueue.append(data)
        }
    }
}

// MARK: - Server Delegate Implementation

/// CustomServerDelegate demonstrates handling server lifecycle and custom requests
class CustomServerDelegate: MCPServerDelegate {
    private var customHandlers: [String: (JSONRPCRequest) async -> Result<AnyCodable, JSONRPCError>] = [:]
    
    init() {
        setupCustomHandlers()
    }
    
    private func setupCustomHandlers() {
        // Register custom method handlers
        customHandlers["custom/status"] = { request in
            .success(AnyCodable([
                "status": "operational",
                "timestamp": Date().ISO8601Format(),
                "version": "1.0.0"
            ]))
        }
        
        customHandlers["custom/echo"] = { request in
            guard let params = request.params?.value as? [String: Any],
                  let message = params["message"] as? String else {
                return .failure(JSONRPCError.invalidParams())
            }
            
            return .success(AnyCodable([
                "echoed": message,
                "timestamp": Date().ISO8601Format()
            ]))
        }
    }
    
    func server(_ server: MCPServer, didReceiveRequest request: JSONRPCRequest) async -> Result<AnyCodable, JSONRPCError> {
        // Handle custom requests
        if let handler = customHandlers[request.method] {
            return await handler(request)
        }
        
        // Unknown method
        return .failure(JSONRPCError.methodNotFound(method: request.method))
    }
    
    func server(_ server: MCPServer, didReceiveNotification notification: JSONRPCNotification) async {
        print("📨 Received notification: \(notification.method)")
        
        switch notification.method {
        case "custom/log":
            if let params = notification.params?.value as? [String: Any],
               let message = params["message"] as? String {
                print("📝 Log from client: \(message)")
            }
            
        case "custom/metrics":
            if let params = notification.params?.value as? [String: Any] {
                print("📊 Metrics received: \(params)")
            }
            
        default:
            print("⚠️ Unknown notification: \(notification.method)")
        }
    }
    
    func serverDidInitialize(_ server: MCPServer) async {
        print("✅ Server initialized successfully")
        
        // Perform post-initialization setup
        await registerDynamicTools(on: server)
    }
    
    func serverWillShutdown(_ server: MCPServer) async {
        print("🛑 Server shutting down...")
        
        // Perform cleanup
        await performCleanup()
    }
    
    private func registerDynamicTools(on server: MCPServer) async {
        // Register tools after initialization based on client capabilities
        let dynamicTool = SimpleTool(
            name: "dynamic_tool",
            title: "Dynamically Registered Tool",
            handler: { _ in
                MCPToolResult.success(text: "This tool was registered after initialization")
            }
        )
        
        await server.registerTool(dynamicTool)
        print("🔧 Dynamic tool registered")
    }
    
    private func performCleanup() async {
        // Clean up resources
        print("🧹 Cleanup completed")
    }
}

// MARK: - Usage Example

@main
struct ServerWithCustomTransportExample {
    static func main() async throws {
        print("=== MCPServer with Custom Transport Example ===\n")
        
        // 1. Create server using the new factory method with delegate
        let delegate = CustomServerDelegate()
        let server = await MCPServer.create(
            name: "custom-transport-server",
            version: "1.0.0",
            title: "Server with Custom Transport",
            instructions: "Demonstrates custom transport and delegate patterns",
            delegate: delegate
        )
        
        // 2. Register initial capabilities
        await server.registerTool(SimpleTool(
            name: "ping",
            title: "Ping Tool",
            handler: { _ in
                MCPToolResult.success(text: "Pong! Server time: \(Date().ISO8601Format())")
            }
        ))
        
        await server.registerResource(SimpleResource(
            resource: MCPResource(
                uri: "config://server",
                title: "Server Configuration",
                text: """
                {
                    "transport": "WebSocket",
                    "features": ["tools", "resources", "custom-methods"]
                }
                """
            )
        ))
        
        // 3. Create and configure custom transport
        let transport = CustomWebSocketTransport()
        transport.setServer(server)
        
        // 4. Start the transport (but not using server.start() to demonstrate handleMessage)
        try await transport.start()
        
        print("\n--- Simulating Client Interactions ---\n")
        
        // 5. Simulate client sending initialize request
        let initRequest = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {
                    "tools": {"listChanged": true},
                    "resources": {"subscribe": true}
                },
                "clientInfo": {
                    "name": "example-client",
                    "version": "1.0.0"
                }
            }
        }
        """
        
        print("Client → Server: initialize")
        transport.simulateIncomingMessage(initRequest)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 6. Send initialized notification
        let initializedNotification = """
        {
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }
        """
        
        print("Client → Server: initialized notification")
        transport.simulateIncomingMessage(initializedNotification)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 7. Test custom method via delegate
        let customRequest = """
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "custom/echo",
            "params": {
                "message": "Hello from custom transport!"
            }
        }
        """
        
        print("Client → Server: custom/echo")
        transport.simulateIncomingMessage(customRequest)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 8. Test tool execution
        let toolRequest = """
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "ping"
            }
        }
        """
        
        print("Client → Server: tools/call (ping)")
        transport.simulateIncomingMessage(toolRequest)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 9. Send custom notification
        let customNotification = """
        {
            "jsonrpc": "2.0",
            "method": "custom/log",
            "params": {
                "message": "Client application started successfully"
            }
        }
        """
        
        print("Client → Server: custom/log notification")
        transport.simulateIncomingMessage(customNotification)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 10. Demonstrate direct message handling (useful for testing or bridging)
        print("\n--- Direct Message Handling ---\n")
        
        let directMessage = """
        {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "custom/status"
        }
        """.data(using: .utf8)!
        
        if let response = await server.handleMessage(directMessage) {
            if let responseStr = String(data: response, encoding: .utf8) {
                print("Direct response: \(responseStr)")
            }
        }
        
        // 11. Graceful shutdown
        print("\n--- Shutting Down ---\n")
        
        await server.shutdown()
        await transport.stop()
        
        print("\n✅ Example completed successfully")
    }
}

// MARK: - Key Takeaways

/*
 This example demonstrates:
 
 1. **MCPServer.create()** - Factory method with delegate
 2. **MCPServer.handleMessage()** - Direct message handling for custom transports
 3. **MCPServer.shutdown()** - Graceful shutdown
 4. **MCPServerDelegate** - Handling custom methods and lifecycle events
 5. **Custom Transport** - Building WebSocket or other transport layers
 6. **Dynamic Registration** - Adding tools/resources after initialization
 
 Key APIs used:
 - `MCPServer.create(name:version:title:instructions:delegate:)`
 - `MCPServer.handleMessage(_:) -> Data?`
 - `MCPServer.shutdown()`
 - `MCPServer.setDelegate(_:)`
 - `MCPServerDelegate` protocol methods
 */
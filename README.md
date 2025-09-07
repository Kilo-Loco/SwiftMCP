# SwiftMCP

A modern, type-safe Swift framework for building Model Context Protocol (MCP) servers.

## Overview

SwiftMCP is a pure Swift implementation of the Model Context Protocol, designed to make it easy to create MCP servers that can provide tools, resources, and prompts to AI assistants.

## Features

- 🚀 **Simple API**: Get started with just a few lines of code
- 🔧 **Type-Safe**: Leverage Swift's type system for safer code
- 🏗️ **Builder Pattern**: Intuitive server configuration
- 📦 **Modular Design**: Use only what you need
- ⚡ **Async/Await**: Modern Swift concurrency
- 🔌 **Extensible**: Easy to add custom tools, resources, and prompts
- 🚨 **Error Handling**: Comprehensive error reporting

## Installation

### Swift Package Manager

Add SwiftMCP to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftMCP.git", from: "1.0.0")
]
```

## Quick Start

### Simple Server

```swift
import SwiftMCP
import SwiftMCPTools
import SwiftMCPTransports

@main
struct MyServer {
    static func main() async throws {
        // Create server with builder
        let server = await MCPServer.builder(name: "my-server", version: "1.0.0")
            .withTitle("My MCP Server")
            .withTool(CalculatorTool())
            .build()
        
        // Start with stdio transport
        try await server.start(transport: StdioTransport())
        
        // Keep running
        try await Task.sleep(nanoseconds: .max)
    }
}
```

### Custom Tool

```swift
struct MyCustomTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "my_tool",
        title: "My Custom Tool",
        description: "Does something useful"
    )
    
    func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        // Tool implementation
        return MCPToolResult.success(text: "Tool executed!")
    }
}
```

### Simple Tool with Closure

```swift
let echoTool = SimpleTool(
    name: "echo",
    title: "Echo Tool",
    description: "Echoes input",
    inputSchema: [
        "type": "object",
        "properties": [
            "message": ["type": "string"]
        ]
    ],
    handler: { arguments in
        let message = arguments?["message"] as? String ?? ""
        return MCPToolResult.success(text: "Echo: \(message)")
    }
)
```

### Resources

```swift
// Static resource
let configResource = SimpleResource(
    resource: MCPResource(
        uri: "config://settings",
        title: "Settings",
        mimeType: "application/json",
        text: "{ \"theme\": \"dark\" }"
    )
)

// Dynamic resource
let dynamicResource = DynamicResource(
    uri: "data://metrics",
    title: "Live Metrics",
    updateHandler: { 
        // Fetch current data
        let metrics = await fetchMetrics()
        return MCPResource(
            uri: "data://metrics",
            text: metrics.toJSON()
        )
    }
)
```

### Prompts

```swift
let greetingPrompt = SimplePrompt(
    name: "greeting",
    title: "Greeting Generator",
    arguments: [
        MCPPromptArgument(name: "name", required: true)
    ],
    generator: { arguments in
        let name = arguments?["name"] ?? "World"
        return [
            .system("You are a friendly assistant."),
            .user("Greet \(name) warmly.")
        ]
    }
)
```

## Architecture

### Core Components

- **MCPServer**: Main server actor handling protocol lifecycle
- **MCPToolExecutor**: Protocol for implementing tools
- **MCPResourceProvider**: Protocol for providing resources
- **MCPPromptProvider**: Protocol for generating prompts
- **MCPTransport**: Abstract transport layer

### Modules

- **SwiftMCP**: Core framework with protocol implementation
- **SwiftMCPTools**: Common tools library (calculator, etc.)
- **SwiftMCPTransports**: Transport implementations (stdio, HTTP, WebSocket)

## Advanced Usage

### Custom Transport

```swift
struct MyTransport: MCPTransport {
    func start() async throws { /* ... */ }
    func send(_ data: Data) async throws { /* ... */ }
    func receive() async throws -> Data { /* ... */ }
    func stop() async { /* ... */ }
}
```

### Server Delegate

```swift
class MyDelegate: MCPServerDelegate {
    func server(_ server: MCPServer, didReceiveRequest request: JSONRPCRequest) async -> Result<AnyCodable, JSONRPCError> {
        // Handle custom requests
    }
    
    func serverDidInitialize(_ server: MCPServer) async {
        // Server initialized
    }
}
```

### Complete Server Example

```swift
let server = await MCPServer.builder(name: "complete-server", version: "2.0.0")
    .withTitle("Complete MCP Server")
    .withInstructions("Full-featured MCP server example")
    // Tools
    .withTools([
        CalculatorTool(),
        MyCustomTool(),
        echoTool
    ])
    .withToolsListChanged()
    // Resources
    .withResources([
        configResource,
        dynamicResource
    ])
    .withResourcesListChanged()
    .withResourcesSubscribe()
    // Prompts
    .withPrompts([
        greetingPrompt,
        codeReviewPrompt
    ])
    .withPromptsListChanged()
    // Capabilities
    .withLogging()
    .build()

// Set delegate
server.delegate = MyDelegate()

// Start server
try await server.start(transport: StdioTransport())
```

## Protocol Compliance

SwiftMCP implements the Model Context Protocol specification 2025-06-18:

- ✅ JSON-RPC 2.0 message format
- ✅ Initialization and lifecycle management
- ✅ Tools capability
- ✅ Resources capability with subscriptions
- ✅ Prompts capability
- ✅ Logging capability
- ✅ Error handling

## Requirements

- Swift 6.0+
- macOS 14.0+ / iOS 17.0+ / tvOS 17.0+ / watchOS 10.0+ / visionOS 1.0+

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Links

- [Model Context Protocol Specification](https://modelcontextprotocol.io)
- [MCP GitHub](https://github.com/modelcontextprotocol)
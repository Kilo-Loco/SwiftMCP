# SwiftMCP Examples

This directory contains comprehensive examples demonstrating various features and patterns in SwiftMCP.

## 📚 Example Categories

### Core Examples
- **SimpleServer.swift** - Basic MCP server with tools, resources, and prompts
- **ServerWithCustomTransport.swift** - Using custom transports with the public APIs
- **StdioTransportWithDelegate.swift** - StdioTransport delegate and AsyncStream patterns
- **ServerLifecycleManagement.swift** - Complete server lifecycle management

### Concurrency Examples (Swift 6)
- **ActorBasedToolExample.swift** - Actor-isolated tools with proper concurrency
- **DynamicResourceExample.swift** - Dynamic resources with real-time updates
- **AsyncPromptExample.swift** - Async prompt generation with external data
- **ConcurrentOperationsExample.swift** - Handling concurrent requests safely
- **CustomProtocolImplementations.swift** - Implementing protocols with `nonisolated`

## 🚀 Quick Start

### Running SimpleServer
```bash
swift run SimpleServer
```

### Running with Custom Transport
```bash
swift run ServerWithCustomTransport
```

### Interactive Server with Stdio
```bash
swift run StdioTransportWithDelegate interactive
```

## 🔑 Key API Patterns

### 1. Server Creation with Delegate
```swift
// Using factory method
let server = await MCPServer.create(
    name: "my-server",
    version: "1.0.0",
    delegate: myDelegate
)

// Using builder pattern
let server = await MCPServer.builder(name: "my-server", version: "1.0.0")
    .withDelegate(myDelegate)
    .build()
```

### 2. Direct Message Handling
```swift
// Process messages directly (useful for custom transports)
let response = await server.handleMessage(jsonRpcData)
if let response = response {
    // Send response back through transport
}
```

### 3. StdioTransport with Delegate
```swift
let transport = StdioTransport()
await transport.setDelegate(myTransportDelegate)

// Or use AsyncStream
let dataStream = await transport.receivedData
for await data in dataStream {
    // Process data
}
```

### 4. Graceful Shutdown
```swift
// Properly shutdown server
await server.shutdown()
await transport.stop()
```

## 🏗️ Architecture Patterns

### Actor-Based Tools
Tools that manage state using actors for thread-safety:
```swift
struct DatabaseQueryTool: MCPToolExecutor {
    private let connectionPool = DatabaseConnectionPool()
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        // Safe async execution
        return try await connectionPool.executeQuery(...)
    }
}
```

### Dynamic Resources
Resources that update in real-time:
```swift
class SystemMetricsResource: MCPResourceProvider {
    nonisolated func read() async throws -> MCPResource {
        // Fetch current metrics
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // Send updates when metrics change
    }
}
```

### Async Prompt Generation
Prompts that fetch context from external sources:
```swift
struct CodeReviewPrompt: MCPPromptProvider {
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        // Fetch context in parallel
        async let bestPractices = knowledgeBase.search(...)
        async let userContext = apiClient.fetchUserContext(...)
        
        // Generate comprehensive prompt
    }
}
```

## 📋 Examples by Use Case

### Building a Custom Transport
See: `ServerWithCustomTransport.swift`
- Implement MCPTransport protocol
- Use `server.handleMessage()` for processing
- Handle responses asynchronously

### Monitoring and Metrics
See: `ServerLifecycleManagement.swift`
- Track server health
- Collect performance metrics
- Implement graceful shutdown

### Concurrent Request Handling
See: `ConcurrentOperationsExample.swift`
- Handle multiple clients
- Rate limiting
- Stress testing

### Protocol Implementation
See: `CustomProtocolImplementations.swift`
- Proper `nonisolated` usage
- Actor isolation patterns
- Generic implementations

## 🧪 Testing Examples

Each example includes patterns that can be used in tests:

1. **Direct Testing** - Use `handleMessage()` to test server without transport
2. **Delegate Testing** - Mock delegates to verify callbacks
3. **Concurrent Testing** - Stress test with multiple concurrent operations
4. **Lifecycle Testing** - Test initialization, runtime, and shutdown

## 📖 Documentation

Each example file contains:
- Detailed inline comments
- Key concepts section at the end
- Usage instructions
- Best practices

## 🔗 Related Documentation

- [SwiftMCP README](../README.md)
- [API Enhancement Report](../../xamrock-client/SwiftMCP_API_Enhancement_Report.md)
- [Concurrency Bug Report](../../xamrock-client/SwiftMCP_Bug_Report.md)

## 💡 Tips

1. **Start Simple**: Begin with `SimpleServer.swift` to understand basics
2. **Learn Concurrency**: Study the actor-based examples for Swift 6
3. **Custom Transports**: Use `ServerWithCustomTransport.swift` as a template
4. **Production Ready**: Follow patterns in `ServerLifecycleManagement.swift`

## 🤝 Contributing

When adding new examples:
1. Follow the existing file naming pattern
2. Include comprehensive comments
3. Add a "Key Concepts" section
4. Update this README
5. Ensure Swift 6 strict concurrency compliance
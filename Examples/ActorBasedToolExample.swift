//
//  ActorBasedToolExample.swift
//  SwiftMCP Examples
//
//  Demonstrates implementing an MCPToolExecutor with proper actor isolation
//  This example shows how to safely manage state in a concurrent environment
//

import Foundation
import SwiftMCP

// MARK: - Actor-Based Tool with State Management

/// DatabaseQueryTool demonstrates a tool that uses an actor to manage database connections
/// and query state safely across concurrent executions.
///
/// Key concepts demonstrated:
/// - Actor isolation for state management
/// - Proper implementation of nonisolated protocol methods
/// - Safe concurrent access patterns
/// - Connection pooling with actor protection
actor DatabaseConnectionPool {
    private var connections: [DatabaseConnection] = []
    private var activeQueries = 0
    private let maxConnections = 5
    
    init() {
        // Initialize connection pool
        for i in 0..<maxConnections {
            connections.append(DatabaseConnection(id: i))
        }
    }
    
    func executeQuery(_ query: String) async throws -> String {
        activeQueries += 1
        defer { activeQueries -= 1 }
        
        // Get available connection
        guard let connection = connections.first(where: { $0.isAvailable }) else {
            throw DatabaseError.noAvailableConnections
        }
        
        connection.isAvailable = false
        defer { connection.isAvailable = true }
        
        // Simulate query execution
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        return "Query result for: \(query) (connection: \(connection.id))"
    }
    
    var status: String {
        "Active queries: \(activeQueries), Available connections: \(connections.filter { $0.isAvailable }.count)"
    }
}

class DatabaseConnection {
    let id: Int
    var isAvailable = true
    
    init(id: Int) {
        self.id = id
    }
}

enum DatabaseError: Error {
    case noAvailableConnections
    case invalidQuery
}

/// DatabaseQueryTool shows the proper way to implement MCPToolExecutor with actor-based state
struct DatabaseQueryTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "database_query",
        title: "Database Query Tool",
        description: "Executes database queries with connection pooling",
        inputSchema: [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "SQL query to execute"
                ],
                "timeout": [
                    "type": "number",
                    "description": "Query timeout in seconds"
                ]
            ],
            "required": ["query"]
        ]
    )
    
    private let connectionPool = DatabaseConnectionPool()
    
    /// This method MUST be marked as nonisolated to comply with the protocol
    /// It can safely call into the actor using await
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let query = arguments?["query"] as? String else {
            return MCPToolResult.error("Missing or invalid query parameter")
        }
        
        // Validate query (basic example)
        guard !query.isEmpty, query.count < 1000 else {
            return MCPToolResult.error("Query is empty or too long")
        }
        
        do {
            // Execute query through the actor - this is safe!
            let result = try await connectionPool.executeQuery(query)
            let status = await connectionPool.status
            
            return MCPToolResult(
                content: [
                    .text(MCPTextContent(
                        text: result,
                        annotations: MCPAnnotations(
                            audience: ["developer"],
                            metadata: ["pool_status": status]
                        )
                    ))
                ],
                isError: false
            )
        } catch DatabaseError.noAvailableConnections {
            return MCPToolResult.error("All database connections are busy. Please try again.")
        } catch {
            return MCPToolResult.error("Database error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Analytics Tool with Metrics Tracking

/// AnalyticsTool demonstrates thread-safe metrics collection
actor MetricsCollector {
    private var metrics: [String: Int] = [:]
    private var timestamps: [Date] = []
    
    func recordEvent(_ event: String) {
        metrics[event, default: 0] += 1
        timestamps.append(Date())
        
        // Keep only last 1000 timestamps for memory efficiency
        if timestamps.count > 1000 {
            timestamps.removeFirst()
        }
    }
    
    func getMetrics() -> [String: Any] {
        [
            "events": metrics,
            "total_events": metrics.values.reduce(0, +),
            "unique_events": metrics.keys.count,
            "last_event": timestamps.last?.ISO8601Format() ?? "never"
        ]
    }
    
    func reset() {
        metrics.removeAll()
        timestamps.removeAll()
    }
}

struct AnalyticsTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "analytics",
        title: "Analytics Tool",
        description: "Tracks and reports analytics metrics",
        inputSchema: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["track", "report", "reset"],
                    "description": "Action to perform"
                ],
                "event": [
                    "type": "string",
                    "description": "Event name (required for track action)"
                ]
            ],
            "required": ["action"]
        ]
    )
    
    private let collector = MetricsCollector()
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let action = arguments?["action"] as? String else {
            return MCPToolResult.error("Missing action parameter")
        }
        
        switch action {
        case "track":
            guard let event = arguments?["event"] as? String else {
                return MCPToolResult.error("Missing event parameter for track action")
            }
            await collector.recordEvent(event)
            return MCPToolResult.success(text: "Event '\(event)' tracked successfully")
            
        case "report":
            let metrics = await collector.getMetrics()
            let jsonData = try JSONSerialization.data(withJSONObject: metrics, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return MCPToolResult.success(text: jsonString)
            
        case "reset":
            await collector.reset()
            return MCPToolResult.success(text: "Analytics metrics reset")
            
        default:
            return MCPToolResult.error("Unknown action: \(action)")
        }
    }
}

// MARK: - Cache Management Tool

/// CacheTool shows proper cache management with expiration
actor CacheManager {
    private struct CacheEntry {
        let value: String
        let expiresAt: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let defaultTTL: TimeInterval = 300 // 5 minutes
    
    func get(_ key: String) -> String? {
        if let entry = cache[key] {
            if entry.expiresAt > Date() {
                return entry.value
            } else {
                // Remove expired entry
                cache.removeValue(forKey: key)
            }
        }
        return nil
    }
    
    func set(_ key: String, value: String, ttl: TimeInterval? = nil) {
        let expiresAt = Date().addingTimeInterval(ttl ?? defaultTTL)
        cache[key] = CacheEntry(value: value, expiresAt: expiresAt)
    }
    
    func invalidate(_ key: String) {
        cache.removeValue(forKey: key)
    }
    
    func clear() {
        cache.removeAll()
    }
    
    func stats() -> [String: Any] {
        let now = Date()
        let validEntries = cache.values.filter { $0.expiresAt > now }
        return [
            "total_entries": cache.count,
            "valid_entries": validEntries.count,
            "expired_entries": cache.count - validEntries.count,
            "keys": Array(cache.keys)
        ]
    }
}

struct CacheTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "cache",
        title: "Cache Management Tool",
        description: "Manages application cache with TTL support",
        inputSchema: [
            "type": "object",
            "properties": [
                "operation": [
                    "type": "string",
                    "enum": ["get", "set", "invalidate", "clear", "stats"],
                    "description": "Cache operation"
                ],
                "key": [
                    "type": "string",
                    "description": "Cache key"
                ],
                "value": [
                    "type": "string",
                    "description": "Value to cache (for set operation)"
                ],
                "ttl": [
                    "type": "number",
                    "description": "Time to live in seconds (optional, default 300)"
                ]
            ],
            "required": ["operation"]
        ]
    )
    
    private let cacheManager = CacheManager()
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let operation = arguments?["operation"] as? String else {
            return MCPToolResult.error("Missing operation parameter")
        }
        
        switch operation {
        case "get":
            guard let key = arguments?["key"] as? String else {
                return MCPToolResult.error("Missing key parameter")
            }
            
            if let value = await cacheManager.get(key) {
                return MCPToolResult.success(text: value)
            } else {
                return MCPToolResult(
                    content: [.text(MCPTextContent(text: "Cache miss for key: \(key)"))],
                    isError: false
                )
            }
            
        case "set":
            guard let key = arguments?["key"] as? String,
                  let value = arguments?["value"] as? String else {
                return MCPToolResult.error("Missing key or value parameter")
            }
            
            let ttl = arguments?["ttl"] as? TimeInterval
            await cacheManager.set(key, value: value, ttl: ttl)
            return MCPToolResult.success(text: "Cached value for key: \(key)")
            
        case "invalidate":
            guard let key = arguments?["key"] as? String else {
                return MCPToolResult.error("Missing key parameter")
            }
            
            await cacheManager.invalidate(key)
            return MCPToolResult.success(text: "Invalidated cache for key: \(key)")
            
        case "clear":
            await cacheManager.clear()
            return MCPToolResult.success(text: "Cache cleared")
            
        case "stats":
            let stats = await cacheManager.stats()
            let jsonData = try JSONSerialization.data(withJSONObject: stats, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return MCPToolResult.success(text: jsonString)
            
        default:
            return MCPToolResult.error("Unknown operation: \(operation)")
        }
    }
}

// MARK: - Usage Example

func demonstrateActorBasedTools() async throws {
    let registry = MCPToolRegistry()
    
    // Register all actor-based tools
    await registry.register(DatabaseQueryTool())
    await registry.register(AnalyticsTool())
    await registry.register(CacheTool())
    
    // Example: Execute database queries concurrently
    await withTaskGroup(of: MCPToolResult?.self) { group in
        for i in 1...5 {
            group.addTask {
                try? await registry.execute(
                    name: "database_query",
                    arguments: ["query": "SELECT * FROM users WHERE id = \(i)"]
                )
            }
        }
        
        for await result in group {
            if let result = result {
                print("Query result: \(result)")
            }
        }
    }
    
    // Example: Track analytics events
    for event in ["page_view", "button_click", "form_submit", "page_view"] {
        _ = try await registry.execute(
            name: "analytics",
            arguments: ["action": "track", "event": event]
        )
    }
    
    // Get analytics report
    let report = try await registry.execute(
        name: "analytics",
        arguments: ["action": "report"]
    )
    print("Analytics report: \(report)")
    
    // Example: Use cache
    _ = try await registry.execute(
        name: "cache",
        arguments: ["operation": "set", "key": "user:123", "value": "John Doe", "ttl": 60]
    )
    
    let cachedValue = try await registry.execute(
        name: "cache",
        arguments: ["operation": "get", "key": "user:123"]
    )
    print("Cached value: \(cachedValue)")
}

// MARK: - Best Practices Summary

/*
 Actor-Based Tool Best Practices:
 
 1. **Always mark execute as nonisolated**: The protocol method must be nonisolated to work properly
    with Swift 6 concurrency.
 
 2. **Use actors for state management**: Encapsulate mutable state in actors to ensure thread safety.
 
 3. **Avoid blocking operations**: Use async/await for I/O operations to prevent blocking.
 
 4. **Handle errors gracefully**: Return MCPToolResult.error() for user-facing errors.
 
 5. **Resource management**: Use defer blocks to ensure resources are properly released.
 
 6. **Validate inputs**: Always validate arguments before processing.
 
 7. **Provide meaningful responses**: Include helpful error messages and structured data.
 
 8. **Consider performance**: Use connection pooling, caching, and other optimizations for
    frequently accessed resources.
 
 9. **Document schemas**: Provide clear input and output schemas for tool discovery.
 
 10. **Test concurrent access**: Ensure your tools work correctly under concurrent load.
 */
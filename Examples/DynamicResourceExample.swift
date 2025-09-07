//
//  DynamicResourceExample.swift
//  SwiftMCP Examples
//
//  Demonstrates implementing MCPResourceProvider with dynamic content and actor-based state
//  Shows how to handle subscriptions and real-time updates safely
//

import Foundation
import SwiftMCP

// MARK: - System Metrics Resource

/// SystemMetricsMonitor manages system metrics collection with actor isolation
actor SystemMetricsMonitor {
    struct Metrics {
        let timestamp: Date
        let cpuUsage: Double
        let memoryUsage: Double
        let diskUsage: Double
        let networkBandwidth: Double
        let activeConnections: Int
    }
    
    private var currentMetrics: Metrics
    private var historicalMetrics: [Metrics] = []
    private let maxHistory = 100
    private var updateTask: Task<Void, Never>?
    
    init() {
        self.currentMetrics = Metrics(
            timestamp: Date(),
            cpuUsage: 0.0,
            memoryUsage: 0.0,
            diskUsage: 0.0,
            networkBandwidth: 0.0,
            activeConnections: 0
        )
    }
    
    func startMonitoring() {
        guard updateTask == nil else { return }
        
        updateTask = Task {
            while !Task.isCancelled {
                await updateMetrics()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
            }
        }
    }
    
    func stopMonitoring() {
        updateTask?.cancel()
        updateTask = nil
    }
    
    private func updateMetrics() {
        // Simulate metrics collection (in real app, would query system)
        let newMetrics = Metrics(
            timestamp: Date(),
            cpuUsage: Double.random(in: 10...90),
            memoryUsage: Double.random(in: 30...80),
            diskUsage: Double.random(in: 40...60),
            networkBandwidth: Double.random(in: 0...100),
            activeConnections: Int.random(in: 5...50)
        )
        
        currentMetrics = newMetrics
        historicalMetrics.append(newMetrics)
        
        // Keep history bounded
        if historicalMetrics.count > maxHistory {
            historicalMetrics.removeFirst()
        }
    }
    
    func getCurrentMetrics() -> Metrics {
        currentMetrics
    }
    
    func getHistoricalMetrics(last: Int = 10) -> [Metrics] {
        Array(historicalMetrics.suffix(last))
    }
    
    func getMetricsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = [
            "current": [
                "timestamp": currentMetrics.timestamp.ISO8601Format(),
                "cpu_usage": currentMetrics.cpuUsage,
                "memory_usage": currentMetrics.memoryUsage,
                "disk_usage": currentMetrics.diskUsage,
                "network_bandwidth": currentMetrics.networkBandwidth,
                "active_connections": currentMetrics.activeConnections
            ],
            "summary": [
                "avg_cpu": historicalMetrics.map { $0.cpuUsage }.reduce(0, +) / Double(max(historicalMetrics.count, 1)),
                "avg_memory": historicalMetrics.map { $0.memoryUsage }.reduce(0, +) / Double(max(historicalMetrics.count, 1)),
                "peak_connections": historicalMetrics.map { $0.activeConnections }.max() ?? 0
            ]
        ] as [String: Any]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
}

/// SystemMetricsResource demonstrates a dynamic resource with real-time updates
class SystemMetricsResource: MCPResourceProvider {
    private let monitor = SystemMetricsMonitor()
    private var subscribers: [@Sendable (MCPResource) -> Void] = []
    private var subscriptionTask: Task<Void, Never>?
    
    var definition: MCPResource {
        get async {
            MCPResource(
                uri: "system://metrics",
                title: "System Metrics",
                description: "Real-time system performance metrics",
                mimeType: "application/json"
            )
        }
    }
    
    init() {
        Task {
            await monitor.startMonitoring()
        }
    }
    
    deinit {
        subscriptionTask?.cancel()
        Task {
            await monitor.stopMonitoring()
        }
    }
    
    nonisolated func read() async throws -> MCPResource {
        let metricsJSON = await monitor.getMetricsJSON()
        return MCPResource(
            uri: "system://metrics",
            title: "System Metrics",
            description: "Real-time system performance metrics",
            mimeType: "application/json",
            text: metricsJSON,
            annotations: MCPAnnotations(
                audience: ["ops", "developers"],
                metadata: ["refresh_rate": "1s"]
            )
        )
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // Start subscription updates
        await startSubscriptionUpdates(handler: handler)
    }
    
    private func startSubscriptionUpdates(handler: @escaping @Sendable (MCPResource) -> Void) async {
        // Send initial data
        if let resource = try? await read() {
            handler(resource)
        }
        
        // Start periodic updates
        subscriptionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
                if let resource = try? await read() {
                    handler(resource)
                }
            }
        }
    }
    
    nonisolated func unsubscribe() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }
}

// MARK: - Configuration Resource with Version Control

/// ConfigurationManager manages application configuration with versioning
actor ConfigurationManager {
    struct ConfigVersion {
        let version: Int
        let timestamp: Date
        let config: [String: Any]
        let author: String
    }
    
    private var currentVersion: ConfigVersion
    private var versionHistory: [ConfigVersion] = []
    private let maxVersions = 10
    
    init() {
        self.currentVersion = ConfigVersion(
            version: 1,
            timestamp: Date(),
            config: Self.defaultConfig(),
            author: "system"
        )
        versionHistory.append(currentVersion)
    }
    
    private static func defaultConfig() -> [String: Any] {
        [
            "app": [
                "name": "SwiftMCP Server",
                "version": "1.0.0",
                "environment": "development"
            ],
            "features": [
                "tools": true,
                "resources": true,
                "prompts": true,
                "logging": true
            ],
            "limits": [
                "max_connections": 100,
                "timeout": 30,
                "max_payload_size": 1048576
            ]
        ]
    }
    
    func getCurrentConfig() -> ConfigVersion {
        currentVersion
    }
    
    func updateConfig(_ updates: [String: Any], author: String) -> ConfigVersion {
        var newConfig = currentVersion.config
        
        // Merge updates
        for (key, value) in updates {
            newConfig[key] = value
        }
        
        let newVersion = ConfigVersion(
            version: currentVersion.version + 1,
            timestamp: Date(),
            config: newConfig,
            author: author
        )
        
        currentVersion = newVersion
        versionHistory.append(newVersion)
        
        // Keep history bounded
        if versionHistory.count > maxVersions {
            versionHistory.removeFirst()
        }
        
        return newVersion
    }
    
    func rollback(to version: Int) -> ConfigVersion? {
        guard let targetVersion = versionHistory.first(where: { $0.version == version }) else {
            return nil
        }
        
        let rolledBack = ConfigVersion(
            version: currentVersion.version + 1,
            timestamp: Date(),
            config: targetVersion.config,
            author: "rollback"
        )
        
        currentVersion = rolledBack
        versionHistory.append(rolledBack)
        
        return rolledBack
    }
    
    func getVersionHistory() -> [ConfigVersion] {
        versionHistory
    }
}

/// ConfigurationResource provides versioned configuration management
struct ConfigurationResource: MCPResourceProvider {
    private let manager = ConfigurationManager()
    
    var definition: MCPResource {
        get async {
            MCPResource(
                uri: "config://app/settings",
                title: "Application Configuration",
                description: "Versioned application configuration",
                mimeType: "application/json"
            )
        }
    }
    
    nonisolated func read() async throws -> MCPResource {
        let config = await manager.getCurrentConfig()
        let history = await manager.getVersionHistory()
        
        let data: [String: Any] = [
            "version": config.version,
            "timestamp": config.timestamp.ISO8601Format(),
            "author": config.author,
            "config": config.config,
            "history": history.map { version in
                [
                    "version": version.version,
                    "timestamp": version.timestamp.ISO8601Format(),
                    "author": version.author
                ]
            }
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return MCPResource(
            uri: "config://app/settings",
            title: "Application Configuration",
            description: "Versioned application configuration",
            mimeType: "application/json",
            text: jsonString
        )
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // For configuration, we might only send updates when config changes
        // This is a simplified example
        if let resource = try? await read() {
            handler(resource)
        }
    }
    
    nonisolated func unsubscribe() async {
        // No continuous updates for config in this example
    }
}

// MARK: - Live Log Stream Resource

/// LogStreamManager manages a live stream of application logs
actor LogStreamManager {
    struct LogEntry {
        let timestamp: Date
        let level: LogLevel
        let message: String
        let source: String
        let metadata: [String: String]
    }
    
    enum LogLevel: String {
        case debug, info, warning, error, critical
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🚨"
            }
        }
    }
    
    private var logs: [LogEntry] = []
    private let maxLogs = 500
    private var filters: Set<LogLevel> = Set(LogLevel.allCases)
    
    private static var allCases: [LogLevel] {
        [.debug, .info, .warning, .error, .critical]
    }
    
    func log(_ message: String, level: LogLevel, source: String, metadata: [String: String] = [:]) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            source: source,
            metadata: metadata
        )
        
        logs.append(entry)
        
        // Keep logs bounded
        if logs.count > maxLogs {
            logs.removeFirst()
        }
    }
    
    func getLogs(limit: Int = 50, levels: Set<LogLevel>? = nil) -> [LogEntry] {
        let filteredLogs = logs.filter { entry in
            (levels ?? filters).contains(entry.level)
        }
        return Array(filteredLogs.suffix(limit))
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    func setFilter(levels: Set<LogLevel>) {
        filters = levels
    }
    
    func getLogsAsText(limit: Int = 50) -> String {
        getLogs(limit: limit)
            .map { entry in
                let timestamp = entry.timestamp.ISO8601Format()
                let metadata = entry.metadata.isEmpty ? "" : " | \(entry.metadata)"
                return "\(timestamp) \(entry.level.emoji) [\(entry.source)] \(entry.message)\(metadata)"
            }
            .joined(separator: "\n")
    }
}

/// LogStreamResource provides live log streaming
class LogStreamResource: MCPResourceProvider {
    private let logManager = LogStreamManager()
    private var logGeneratorTask: Task<Void, Never>?
    
    var definition: MCPResource {
        get async {
            MCPResource(
                uri: "logs://app/stream",
                title: "Application Logs",
                description: "Live application log stream",
                mimeType: "text/plain"
            )
        }
    }
    
    init() {
        // Start generating sample logs
        startLogGeneration()
    }
    
    deinit {
        logGeneratorTask?.cancel()
    }
    
    private func startLogGeneration() {
        logGeneratorTask = Task {
            let sources = ["API", "Database", "Cache", "Auth", "Worker"]
            let messages = [
                ("Request processed successfully", LogStreamManager.LogLevel.info),
                ("Cache hit for key", LogStreamManager.LogLevel.debug),
                ("Database connection established", LogStreamManager.LogLevel.info),
                ("Authentication token expired", LogStreamManager.LogLevel.warning),
                ("Failed to connect to service", LogStreamManager.LogLevel.error),
                ("Memory usage above threshold", LogStreamManager.LogLevel.warning),
                ("Background job completed", LogStreamManager.LogLevel.info),
                ("Rate limit exceeded", LogStreamManager.LogLevel.warning)
            ]
            
            while !Task.isCancelled {
                let source = sources.randomElement()!
                let (message, level) = messages.randomElement()!
                
                await logManager.log(
                    message,
                    level: level,
                    source: source,
                    metadata: ["request_id": UUID().uuidString.prefix(8).lowercased()]
                )
                
                // Random delay between logs
                let delay = UInt64.random(in: 500_000_000...3_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }
    
    nonisolated func read() async throws -> MCPResource {
        let logs = await logManager.getLogsAsText(limit: 100)
        
        return MCPResource(
            uri: "logs://app/stream",
            title: "Application Logs",
            description: "Live application log stream",
            mimeType: "text/plain",
            text: logs
        )
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // Send updates every 2 seconds
        let updateTask = Task {
            while !Task.isCancelled {
                if let resource = try? await read() {
                    handler(resource)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        
        // Store task reference if needed for cleanup
        _ = updateTask
    }
    
    nonisolated func unsubscribe() async {
        // Cleanup if needed
    }
}

// MARK: - Usage Example

func demonstrateDynamicResources() async throws {
    let registry = MCPResourceRegistry()
    
    // Register dynamic resources
    let metricsResource = SystemMetricsResource()
    let configResource = ConfigurationResource()
    let logResource = LogStreamResource()
    
    await registry.register(metricsResource)
    await registry.register(configResource)
    await registry.register(logResource)
    
    // Read current metrics
    let metrics = try await registry.read(uri: "system://metrics")
    print("Current metrics: \(metrics.text ?? "N/A")")
    
    // Subscribe to metrics updates
    let subscriptionId = try await registry.subscribe(uri: "system://metrics") { resource in
        print("Metrics updated: \(resource.text?.prefix(100) ?? "N/A")...")
    }
    
    // Let it run for a bit
    try await Task.sleep(nanoseconds: 5_000_000_000)
    
    // Unsubscribe
    await registry.unsubscribe(uri: "system://metrics", subscriptionId: subscriptionId)
    
    // Read logs
    let logs = try await registry.read(uri: "logs://app/stream")
    print("Recent logs:\n\(logs.text ?? "No logs")")
}

// MARK: - Best Practices Summary

/*
 Dynamic Resource Best Practices:
 
 1. **Use nonisolated for protocol methods**: All MCPResourceProvider methods must be nonisolated.
 
 2. **Actor isolation for state**: Use actors to manage mutable state safely.
 
 3. **Efficient updates**: Only send updates when data actually changes or at reasonable intervals.
 
 4. **Resource cleanup**: Cancel tasks and clean up subscriptions properly.
 
 5. **Bounded data**: Limit historical data to prevent memory growth.
 
 6. **Structured data**: Use appropriate MIME types and structured formats (JSON, etc.).
 
 7. **Metadata and annotations**: Provide helpful metadata for resource discovery.
 
 8. **Error handling**: Handle errors gracefully and provide fallback data when appropriate.
 
 9. **Subscription management**: Track subscriptions and clean them up properly.
 
 10. **Performance**: Consider caching and throttling for frequently accessed resources.
 */
//
//  MCPDebugger.swift
//  SwiftMCP
//
//  Debugging and logging support for SwiftMCP
//

import Foundation
import os.log

/// Debug logging system for MCP
/// Configuration actor for thread-safe settings
private actor LogConfig {
    var level: MCPDebugger.Level = .none
    var logHandler: (@Sendable (String, MCPDebugger.Level, String, String, Int) -> Void)?
    var consoleOutputEnabled = true
    var osLogEnabled = true
    
    func setLevel(_ level: MCPDebugger.Level) {
        self.level = level
    }
    
    func setLogHandler(_ handler: (@Sendable (String, MCPDebugger.Level, String, String, Int) -> Void)?) {
        self.logHandler = handler
    }
    
    func setConsoleOutputEnabled(_ enabled: Bool) {
        self.consoleOutputEnabled = enabled
    }
    
    func setOsLogEnabled(_ enabled: Bool) {
        self.osLogEnabled = enabled
    }
}

public struct MCPDebugger {
    
    /// Logging levels
    public enum Level: Int, Comparable, Sendable {
        case none = 0
        case error = 1
        case warning = 2
        case info = 3
        case verbose = 4
        case trace = 5
        
        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        var symbol: String {
            switch self {
            case .none: return ""
            case .error: return "❌"
            case .warning: return "⚠️"
            case .info: return "ℹ️"
            case .verbose: return "📝"
            case .trace: return "🔍"
            }
        }
        
        var osLogType: OSLogType {
            switch self {
            case .none: return .default
            case .error: return .error
            case .warning: return .info
            case .info: return .info
            case .verbose: return .debug
            case .trace: return .debug
            }
        }
    }
    
    /// Current logging level - wrapped in actor for thread safety
    private static let config = LogConfig()
    
    public static func setLevel(_ level: Level) async {
        await config.setLevel(level)
    }
    
    public static func getLevel() async -> Level {
        await config.level
    }
    
    /// Custom log handler for external logging systems
    public static func setLogHandler(_ handler: (@Sendable (String, Level, String, String, Int) -> Void)?) async {
        await config.setLogHandler(handler)
    }
    
    /// Enable/disable console output
    public static func setConsoleOutputEnabled(_ enabled: Bool) async {
        await config.setConsoleOutputEnabled(enabled)
    }
    
    /// Enable/disable os_log output
    public static func setOsLogEnabled(_ enabled: Bool) async {
        await config.setOsLogEnabled(enabled)
    }
    
    private static let logger = Logger(subsystem: "SwiftMCP", category: "Debug")
    
    /// Log a message (synchronous wrapper for convenience)
    public static func log(
        _ message: String,
        level: Level,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await logAsync(message, level: level, file: file, function: function, line: line)
        }
    }
    
    /// Log a message asynchronously
    public static func logAsync(
        _ message: String,
        level: Level,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        let currentLevel = await config.level
        guard level <= currentLevel else { return }
        
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = Date().ISO8601Format()
        
        // Format message
        let formattedMessage = "\(level.symbol) [\(timestamp)] [\(fileName):\(line)] \(function) - \(message)"
        
        // Console output
        if await config.consoleOutputEnabled {
            print(formattedMessage)
        }
        
        // os_log output
        if await config.osLogEnabled {
            logger.log(level: level.osLogType, "\(message, privacy: .public)")
        }
        
        // Custom handler
        if let handler = await config.logHandler {
            handler(message, level, fileName, function, line)
        }
    }
    
    /// Log an error
    public static func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// Log a warning
    public static func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    /// Log info
    public static func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// Log verbose
    public static func verbose(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .verbose, file: file, function: function, line: line)
    }
    
    /// Log trace
    public static func trace(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .trace, file: file, function: function, line: line)
    }
}

// MARK: - Message Inspector

/// Protocol for inspecting MCP messages
public protocol MCPMessageInspector: AnyObject, Sendable {
    /// Called before sending a message
    func willSend(_ data: Data, type: String) async
    
    /// Called after receiving a message
    func didReceive(_ data: Data, type: String) async
    
    /// Called when an error occurs
    func didFail(_ error: MCPError, context: String) async
}

/// Default message inspector for debugging
public actor MCPDebugInspector: MCPMessageInspector {
    private var messageLog: [(Date, String, Data)] = []
    private let maxLogSize = 100
    
    public init() {}
    
    public func willSend(_ data: Data, type: String) async {
        let message = String(data: data, encoding: .utf8) ?? "Binary data"
        MCPDebugger.trace("Sending \(type): \(message.prefix(200))...")
        
        messageLog.append((Date(), "SEND:\(type)", data))
        if messageLog.count > maxLogSize {
            messageLog.removeFirst()
        }
    }
    
    public func didReceive(_ data: Data, type: String) async {
        let message = String(data: data, encoding: .utf8) ?? "Binary data"
        MCPDebugger.trace("Received \(type): \(message.prefix(200))...")
        
        messageLog.append((Date(), "RECV:\(type)", data))
        if messageLog.count > maxLogSize {
            messageLog.removeFirst()
        }
    }
    
    public func didFail(_ error: MCPError, context: String) async {
        MCPDebugger.error("Error in \(context): \(error.localizedDescription)")
    }
    
    public func getMessageLog() -> [(Date, String, Data)] {
        messageLog
    }
    
    public func clearLog() {
        messageLog.removeAll()
    }
}

// MARK: - Performance Monitoring

/// Performance monitoring for MCP operations
public actor MCPPerformanceMonitor {
    public struct Metric {
        public let operation: String
        public let startTime: Date
        public let endTime: Date
        public let duration: TimeInterval
        public let success: Bool
        
        public var durationMilliseconds: Double {
            duration * 1000
        }
    }
    
    private var metrics: [Metric] = []
    private var activeOperations: [String: Date] = [:]
    
    public init() {}
    
    /// Start tracking an operation
    public func startOperation(_ name: String) {
        activeOperations[name] = Date()
        MCPDebugger.verbose("Started operation: \(name)")
    }
    
    /// End tracking an operation
    public func endOperation(_ name: String, success: Bool = true) {
        guard let startTime = activeOperations.removeValue(forKey: name) else {
            MCPDebugger.warning("Attempted to end non-existent operation: \(name)")
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        let metric = Metric(
            operation: name,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            success: success
        )
        
        metrics.append(metric)
        
        MCPDebugger.verbose("Completed operation: \(name) in \(String(format: "%.2f", duration * 1000))ms")
        
        // Keep only last 1000 metrics
        if metrics.count > 1000 {
            metrics.removeFirst()
        }
    }
    
    /// Get average duration for an operation type
    public func averageDuration(for operation: String) -> TimeInterval? {
        let operationMetrics = metrics.filter { $0.operation == operation }
        guard !operationMetrics.isEmpty else { return nil }
        
        let totalDuration = operationMetrics.reduce(0) { $0 + $1.duration }
        return totalDuration / Double(operationMetrics.count)
    }
    
    /// Get success rate for an operation type
    public func successRate(for operation: String) -> Double? {
        let operationMetrics = metrics.filter { $0.operation == operation }
        guard !operationMetrics.isEmpty else { return nil }
        
        let successCount = operationMetrics.filter { $0.success }.count
        return Double(successCount) / Double(operationMetrics.count)
    }
    
    /// Get all metrics
    public func getAllMetrics() -> [Metric] {
        metrics
    }
    
    /// Clear all metrics
    public func clearMetrics() {
        metrics.removeAll()
        activeOperations.removeAll()
    }
}
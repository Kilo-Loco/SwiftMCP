//
//  Resource.swift
//  SwiftMCP
//
//  Resource capability definitions
//

import Foundation

// MARK: - Resource Provider Protocol

public protocol MCPResourceProvider: Sendable {
    var definition: MCPResource { get async }
    func read() async throws -> MCPResource
    func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws
    func unsubscribe() async
}

// MARK: - Simple Resource Implementation

public struct SimpleResource: MCPResourceProvider {
    private let _definition: MCPResource
    public var definition: MCPResource {
        get async { _definition }
    }
    private let reader: (@Sendable () async throws -> MCPResource)?
    
    public init(resource: MCPResource) {
        self._definition = resource
        self.reader = nil
    }
    
    public init(
        uri: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        reader: @escaping @Sendable () async throws -> MCPResource
    ) {
        self._definition = MCPResource(
            uri: uri,
            title: title,
            description: description,
            mimeType: mimeType
        )
        self.reader = reader
    }
    
    public func read() async throws -> MCPResource {
        if let reader = reader {
            return try await reader()
        }
        return _definition
    }
    
    public func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // Simple implementation doesn't support subscriptions
        throw JSONRPCError(code: -32001, message: "Subscriptions not supported")
    }
    
    public func unsubscribe() async {
        // No-op for simple implementation
    }
}

// MARK: - Dynamic Resource

public actor DynamicResource: MCPResourceProvider {
    public nonisolated var definition: MCPResource {
        get async { await _definition }
    }
    private var _definition: MCPResource
    private var subscribers: [@Sendable (MCPResource) -> Void] = []
    private let updateHandler: (@Sendable () async throws -> MCPResource)?
    
    public init(
        uri: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        initialContent: String? = nil,
        updateHandler: (@Sendable () async throws -> MCPResource)? = nil
    ) {
        self._definition = MCPResource(
            uri: uri,
            title: title,
            description: description,
            mimeType: mimeType,
            text: initialContent
        )
        self.updateHandler = updateHandler
    }
    
    public func read() async throws -> MCPResource {
        if let handler = updateHandler {
            _definition = try await handler()
        }
        return _definition
    }
    
    public func update(_ resource: MCPResource) {
        _definition = resource
        notifySubscribers()
    }
    
    public func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        subscribers.append(handler)
        handler(_definition) // Send current state immediately
    }
    
    public func unsubscribe() async {
        subscribers.removeAll()
    }
    
    private func notifySubscribers() {
        let current = _definition
        for subscriber in subscribers {
            subscriber(current)
        }
    }
}

// MARK: - Resource Registry

public actor MCPResourceRegistry {
    private var resources: [String: MCPResourceProvider] = [:]
    private var subscriptions: [String: Set<UUID>] = [:]
    
    public init() {}
    
    public func register(_ resource: MCPResourceProvider) async {
        let def = await resource.definition
        resources[def.uri] = resource
    }
    
    public func unregister(uri: String) {
        resources.removeValue(forKey: uri)
        subscriptions.removeValue(forKey: uri)
    }
    
    public func get(uri: String) -> MCPResourceProvider? {
        resources[uri]
    }
    
    public func list() async -> [MCPResource] {
        var results: [MCPResource] = []
        for provider in resources.values {
            results.append(await provider.definition)
        }
        return results
    }
    
    public func read(uri: String) async throws -> MCPResource {
        guard let resource = resources[uri] else {
            throw JSONRPCError.methodNotFound(method: "resources/read:\(uri)")
        }
        return try await resource.read()
    }
    
    public func subscribe(
        uri: String,
        handler: @escaping @Sendable (MCPResource) -> Void
    ) async throws -> UUID {
        guard let resource = resources[uri] else {
            throw JSONRPCError.methodNotFound(method: "resources/subscribe:\(uri)")
        }
        
        let subscriptionId = UUID()
        if subscriptions[uri] == nil {
            subscriptions[uri] = Set()
        }
        subscriptions[uri]?.insert(subscriptionId)
        
        try await resource.subscribe(handler: handler)
        return subscriptionId
    }
    
    public func unsubscribe(uri: String, subscriptionId: UUID) async {
        subscriptions[uri]?.remove(subscriptionId)
        
        if subscriptions[uri]?.isEmpty == true {
            if let resource = resources[uri] {
                await resource.unsubscribe()
            }
            subscriptions.removeValue(forKey: uri)
        }
    }
}
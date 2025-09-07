//
//  MCPTransport.swift
//  SwiftMCP
//
//  Transport layer abstraction
//

import Foundation

// MARK: - Transport Protocol

public protocol MCPTransport: Sendable {
    func start() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func stop() async
}

// MARK: - Transport Error

public enum MCPTransportError: LocalizedError {
    case notConnected
    case connectionFailed(Error)
    case sendFailed(Error)
    case receiveFailed(Error)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Transport is not connected"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .sendFailed(let error):
            return "Send failed: \(error.localizedDescription)"
        case .receiveFailed(let error):
            return "Receive failed: \(error.localizedDescription)"
        case .invalidData:
            return "Received invalid data"
        }
    }
}
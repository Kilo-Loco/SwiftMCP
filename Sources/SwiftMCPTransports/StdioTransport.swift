//
//  StdioTransport.swift
//  SwiftMCPTransports
//
//  Standard I/O transport implementation
//

import Foundation
import SwiftMCP
import os.log

// MARK: - StdioTransport Delegate

public protocol StdioTransportDelegate: AnyObject, Sendable {
    func transport(_ transport: StdioTransport, didReceive data: Data) async
    func transportDidConnect(_ transport: StdioTransport) async
    func transportDidDisconnect(_ transport: StdioTransport) async
    func transport(_ transport: StdioTransport, didEncounterError error: Error) async
}

public actor StdioTransport: MCPTransport {
    private let logger = Logger(subsystem: "SwiftMCP", category: "StdioTransport")
    
    private var inputStream: AsyncStream<Data>?
    private var inputContinuation: AsyncStream<Data>.Continuation?
    private var isRunning = false
    
    // Delegate
    private weak var delegate: StdioTransportDelegate?
    
    // Public stream for receiving data
    private var receivedDataStream: AsyncStream<Data>?
    private var receivedDataContinuation: AsyncStream<Data>.Continuation?
    
    public init() {}
    
    /// Sets the delegate for transport callbacks
    public func setDelegate(_ delegate: StdioTransportDelegate?) async {
        self.delegate = delegate
    }
    
    /// Provides an async stream of received data
    public var receivedData: AsyncStream<Data> {
        if let stream = receivedDataStream {
            return stream
        }
        
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        receivedDataStream = stream
        receivedDataContinuation = continuation
        return stream
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        
        // Create async stream for stdin
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.inputStream = stream
        self.inputContinuation = continuation
        
        // Start reading from stdin
        Task {
            await readStdin()
        }
        
        // Notify delegate
        await delegate?.transportDidConnect(self)
        
        logger.info("Stdio transport started")
    }
    
    public func send(_ data: Data) async throws {
        guard isRunning else {
            throw MCPTransportError.notConnected
        }
        
        // Write to stdout with newline delimiter
        var output = data
        if !data.isEmpty && data.last != 0x0A {
            output.append(0x0A) // Add newline
        }
        
        if let outputString = String(data: output, encoding: .utf8) {
            print(outputString, terminator: "")
            fflush(stdout)
        } else {
            throw MCPTransportError.sendFailed(MCPError.encodingError(NSError(domain: "StdioTransport", code: 1)))
        }
    }
    
    public func receive() async throws -> Data {
        guard isRunning, let stream = inputStream else {
            throw MCPTransportError.notConnected
        }
        
        for await data in stream {
            return data
        }
        
        throw MCPTransportError.receiveFailed(MCPError.invalidState("Stream ended"))
    }
    
    public func stop() async {
        isRunning = false
        inputContinuation?.finish()
        inputContinuation = nil
        inputStream = nil
        
        // Finish received data stream
        receivedDataContinuation?.finish()
        receivedDataContinuation = nil
        receivedDataStream = nil
        
        // Notify delegate
        await delegate?.transportDidDisconnect(self)
        
        logger.info("Stdio transport stopped")
    }
    
    private func readStdin() async {
        let inputHandle = FileHandle.standardInput
        
        while isRunning {
            let data = inputHandle.availableData
            
            if data.isEmpty {
                // EOF reached
                break
            }
            
            // Process line-delimited JSON
            var buffer = Data()
            for byte in data {
                buffer.append(byte)
                if byte == 0x0A { // Newline
                    if !buffer.isEmpty {
                        let message = buffer
                        buffer.removeAll()
                        inputContinuation?.yield(message)
                        
                        // Notify delegate
                        if let delegate = self.delegate {
                            await delegate.transport(self, didReceive: message)
                        }
                        
                        // Also send to stream if available
                        receivedDataContinuation?.yield(message)
                    }
                }
            }
        }
        
        inputContinuation?.finish()
    }
}

// MARK: - Convenience Initializer

extension MCPTransport where Self == StdioTransport {
    public static var stdio: MCPTransport {
        StdioTransport()
    }
}
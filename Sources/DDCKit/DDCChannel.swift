import Foundation
import IOKit

/// DDC/CI to one display over its IOAVService I2C bus.
///
/// All bus traffic runs on one serial queue: DDC/CI allows a single outstanding
/// transaction, and the monitor needs a pause after each message before it will answer.
public final class DDCChannel: @unchecked Sendable {
    private let service: CFTypeRef
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingWrites: [VCPCode: UInt16] = [:]
    private var flushScheduled = false

    /// Pause after a write before the display is ready for the next message (DDC/CI §4.3 asks for 50 ms).
    public var settleDelay: TimeInterval = 0.05
    public var attempts = 3
    /// Called on the channel's queue when a queued write fails. Set it before enqueueing writes.
    public var onWriteError: (@Sendable (VCPCode, DDCError) -> Void)?

    init(service: CFTypeRef, label: String) {
        self.service = service
        queue = DispatchQueue(label: "DDCKit.DDC.\(label)", qos: .userInitiated)
    }

    /// One lock file shared by every process using DDCKit (the app and `ddc-control`).
    /// Without it, two processes interleave transactions on the bus and read each other's
    /// replies, which pass the checksum but belong to the wrong request.
    private static let busLockDescriptor: Int32 = open(
        FileManager.default.temporaryDirectory.appending(path: "DDCKit.lock").path, O_CREAT | O_RDWR, 0o600
    )

    private func withBusLock<T>(_ body: () throws -> T) rethrows -> T {
        let fd = Self.busLockDescriptor
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN) } }
        return try body()
    }

    // MARK: Blocking primitives (called on `queue`)

    private func write(_ bytes: [UInt8]) throws {
        guard let writeI2C = IOAV.writeI2C else { throw DDCError.unavailable }
        var buffer = bytes
        let rc = writeI2C(service, DDCProtocol.i2cAddress, DDCProtocol.hostSubaddress, &buffer, UInt32(buffer.count))
        guard rc == kIOReturnSuccess else { throw DDCError.transport(rc) }
    }

    private func read(count: Int) throws -> [UInt8] {
        guard let readI2C = IOAV.readI2C else { throw DDCError.unavailable }
        var buffer = [UInt8](repeating: 0, count: count)
        let rc = readI2C(service, DDCProtocol.i2cAddress, DDCProtocol.hostSubaddress, &buffer, UInt32(count))
        guard rc == kIOReturnSuccess else { throw DDCError.transport(rc) }
        return buffer
    }

    private func pause() { Thread.sleep(forTimeInterval: settleDelay) }

    /// Sends a request and parses the reply, retrying because DDC replies are sometimes
    /// dropped or garbled; the checksum is what tells a good reply from a bad one.
    private func transact<T>(_ request: [UInt8], replyLength: Int, parse: ([UInt8]) -> T?) throws -> T {
        var lastError: DDCError = .noReply
        for _ in 0..<max(attempts, 1) {
            do {
                let parsed = try withBusLock {
                    try write(request)
                    pause()
                    return parse(try read(count: replyLength))
                }
                if let parsed { return parsed }
                lastError = .noReply
            } catch let error as DDCError {
                lastError = error
            }
            pause()
        }
        throw lastError
    }

    private func readVCPOnQueue(_ code: VCPCode) throws -> VCPReading {
        let reply = try transact(DDCProtocol.getVCP(code), replyLength: DDCProtocol.vcpReplyLength) {
            DDCProtocol.parseVCPReply($0, for: code)
        }
        switch reply {
        case .value(let reading): return reading
        case .unsupported: throw DDCError.unsupported(code)
        }
    }

    // MARK: Public API

    public func readVCP(_ code: VCPCode) throws -> VCPReading {
        try queue.sync { try readVCPOnQueue(code) }
    }

    public func writeVCP(_ code: VCPCode, _ value: UInt16) throws {
        try queue.sync {
            try withBusLock {
                try write(DDCProtocol.setVCP(code, value))
                pause()
            }
        }
    }

    /// Reads the capabilities string, fragment by fragment.
    public func capabilities() throws -> Capabilities {
        try queue.sync {
            var bytes: [UInt8] = []
            while bytes.count < 4096 {
                let offset = bytes.count
                let fragment = try transact(DDCProtocol.capabilitiesRequest(offset: offset),
                                            replyLength: DDCProtocol.capabilitiesChunkReadLength) {
                    DDCProtocol.parseCapabilitiesFragment($0, expectedOffset: offset)
                }
                if fragment.isEmpty { break }
                bytes += fragment
            }
            let text = String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
            return Capabilities(parsing: text)
        }
    }

    /// Queues a write that may be superseded: while a write is in flight, later values for
    /// the same code replace earlier ones, so dragging a slider sends only the latest value.
    public func enqueueWrite(_ code: VCPCode, _ value: UInt16) {
        lock.lock()
        pendingWrites[code] = value
        let shouldSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        queue.async { [self] in
            while true {
                lock.lock()
                guard let (code, value) = pendingWrites.min(by: { $0.key < $1.key }) else {
                    flushScheduled = false
                    lock.unlock()
                    return
                }
                pendingWrites[code] = nil
                lock.unlock()
                do {
                    try withBusLock {
                        try write(DDCProtocol.setVCP(code, value))
                        pause()
                    }
                } catch let error as DDCError {
                    onWriteError?(code, error)
                } catch {}
            }
        }
    }

    /// Waits until queued writes have been sent.
    public func drain() {
        queue.sync {}
        lock.lock()
        let busy = flushScheduled
        lock.unlock()
        if busy { drain() }
    }
}

import Darwin
import Foundation

/// Synchronous Discord IPC client over `AF_UNIX`.
///
/// Thread-safety: **not** internally synchronised — the caller confines an instance to one
/// serial queue (see `PresenceEngine`). Hence `@unchecked Sendable`.
public final class DiscordIPCClient: @unchecked Sendable {
    public struct ReadyUser: Equatable, Sendable {
        public let username: String
        public let id: String
    }

    public struct Reply: Equatable, Sendable {
        public let opcode: Opcode
        public let data: String
        public let evt: String

        init(opcode: Opcode, frame: [String: Any]) {
            self.opcode = opcode
            self.data = Self.describe(frame["data"])
            self.evt = (frame["evt"] as? String) ?? ""
        }

        private static func describe(_ value: Any?) -> String {
            guard let value else { return "nil" }
            if value is NSNull { return "null" }
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
                return String(decoding: data, as: UTF8.self)
            }
            return String(describing: value)
        }
    }

    public private(set) var readyUser: ReadyUser?
    public private(set) var path: String?
    public private(set) var lastReply: Reply?

    private var fd: Int32 = -1
    private let appID: String
    private let readTimeout: TimeInterval
    private static let ignoreSIGPIPEOnce: Void = {
        _ = signal(SIGPIPE, SIG_IGN)
    }()

    public init(appID: String, readTimeout: TimeInterval = 3) {
        Self.ignoreSIGPIPEOnce
        self.appID = appID
        self.readTimeout = readTimeout
    }

    public var isConnected: Bool { fd >= 0 }

    deinit { close() }

    // MARK: - connection

    /// Tries every candidate socket, then handshakes. A rejected Application ID is final
    /// (returned immediately); other failures are collected and reported together.
    @discardableResult
    public func connect(pipeIndex: Int = 0) throws -> String {
        let candidates = SocketLocator.candidates(pipeIndex: pipeIndex)
        var failures: [String] = []

        for candidate in candidates {
            do {
                try openSocket(path: candidate)
                try handshake()
                path = candidate
                return candidate
            } catch let error as IPCError {
                close()
                if case .discordRejected = error { throw error }
                failures.append("\(candidate) → \(error)")
            } catch {
                close()
                failures.append("\(candidate) → \(error)")
            }
        }
        throw IPCError.socketUnavailable(failures)
    }

    private func openSocket(path: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw IPCError.io("socket(): \(errnoText())") }

        var on: Int32 = 1
        // Without SO_NOSIGPIPE a peer hangup would kill the process with SIGPIPE.
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: Int(readTimeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw IPCError.io("socket path too long: \(path)") }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = strcpy(destination, path)
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let message = errnoText()
            Darwin.close(descriptor)
            throw IPCError.io("connect(\(path)): \(message)")
        }
        fd = descriptor
    }

    public func close() {
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        fd = -1
        readyUser = nil
    }

    // MARK: - protocol

    private func handshake() throws {
        try write(opcode: .handshake, payload: ["v": 1, "client_id": appID])
        let (op, reply) = try readFrame()
        // Discord answers a bad Application ID by CLOSING with `{"code":4000,...}` — verified
        // against the live client, not against the docs (the docs only describe evt:ERROR).
        if op == .close { throw rejection(fromClose: reply) }
        if reply["evt"] as? String == "ERROR" {
            let (code, message) = IPCProtocol.errorCodeAndMessage(reply["data"])
            throw IPCError.discordRejected(code: code, message: message)
        }
        rememberUser(from: reply)
    }

    private func rejection(fromClose payload: [String: Any]) -> IPCError {
        guard payload["code"] != nil || payload["message"] != nil else {
            return IPCError.discordClosed
        }
        let (code, message) = IPCProtocol.errorCodeAndMessage(payload)
        return IPCError.discordRejected(code: code, message: message)
    }

    private func rememberUser(from frame: [String: Any]) {
        guard let data = frame["data"] as? [String: Any],
              let user = data["user"] as? [String: Any],
              let username = user["username"] as? String
        else { return }
        readyUser = ReadyUser(username: username, id: (user["id"] as? String) ?? "")
    }

    /// Pushes an activity. `nil` clears it (`"activity": null`).
    public func setActivity(_ activityJSON: Data?) throws {
        _ = try setActivityWithReply(activityJSON)
    }

    func setActivityWithReply(_ activityJSON: Data?) throws -> Reply {
        var args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
        if let activityJSON, let object = try? JSONSerialization.jsonObject(with: activityJSON) {
            args["activity"] = object
        } else if activityJSON == nil {
            args["activity"] = NSNull()
        } else {
            throw IPCError.malformedFrame("activity payload is not valid JSON")
        }
        let (reply, _) = try commandReply("SET_ACTIVITY", args: args)
        return reply
    }

    /// Sends a command and waits for its reply (matched by nonce, skipping unrelated events).
    @discardableResult
    public func command(_ name: String, args: [String: Any] = [:]) throws -> [String: Any] {
        let (_, frame) = try commandReply(name, args: args)
        return frame
    }

    private func commandReply(_ name: String, args: [String: Any] = [:]) throws -> (Reply, [String: Any]) {
        let nonce = UUID().uuidString
        try write(opcode: .frame, payload: ["cmd": name, "args": args, "nonce": nonce])
        while true {
            let (op, frame) = try readFrame()
            switch op {
            case .pong:
                continue
            case .ping:
                try write(opcode: .pong, body: Data())
                continue
            case .close:
                lastReply = Reply(opcode: op, frame: frame)
                close()
                throw rejection(fromClose: frame)
            case .frame:
                if frame["nonce"] as? String == nonce || frame["cmd"] as? String == name {
                    let reply = Reply(opcode: op, frame: frame)
                    lastReply = reply
                    if frame["evt"] as? String == "ERROR" {
                        let (code, message) = IPCProtocol.errorCodeAndMessage(frame["data"])
                        throw IPCError.discordRejected(code: code, message: message)
                    }
                    rememberUser(from: frame)
                    return (reply, frame)
                }
                continue
            case .handshake:
                continue
            }
        }
    }

    /// Keepalive. Returns false instead of throwing when the peer is gone.
    public func ping() -> Bool {
        do {
            try write(opcode: .ping, body: Data("{}".utf8))
            while true {
                let (op, _) = try readFrame()
                if op == .pong { return true }
                if op == .close { close(); return false }
                if op == .ping { try write(opcode: .pong, body: Data()); continue }
            }
        } catch {
            close()
            return false
        }
    }

    // MARK: - raw IO

    private func write(opcode: Opcode, payload: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try write(opcode: opcode, body: body)
    }

    private func write(opcode: Opcode, body: Data) throws {
        guard fd >= 0 else { throw IPCError.notConnected }
        let frame = IPCProtocol.encode(opcode: opcode, body: body)
        try frame.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR { continue }
                let code = errno
                let message = String(cString: strerror(code))
                close()
                if code == EPIPE || code == ECONNRESET || code == ENOTCONN || code == EBADF {
                    throw IPCError.discordClosed
                }
                throw IPCError.io("send(): \(message)")
            }
        }
    }

    /// Reads exactly one frame; partial reads are accumulated (a single `recv` is not a frame).
    private func readFrame() throws -> (Opcode, [String: Any]) {
        guard fd >= 0 else { throw IPCError.notConnected }
        let header = try readExact(IPCProtocol.headerSize)
        let rawLength = header.loadLE(at: 4)
        guard rawLength <= UInt32(IPCProtocol.maxFrameSize) else {
            throw IPCError.malformedFrame("frame of \(rawLength) bytes is implausible")
        }
        let body = try readExact(Int(rawLength))
        let (op, payload) = try IPCProtocol.decode(header + body)
        return (op, payload)
    }

    private func readExact(_ count: Int) throws -> Data {
        guard fd >= 0 else { throw IPCError.notConnected }
        var buffer = Data(count: count)
        var offset = 0
        try buffer.withUnsafeMutableBytes { raw in
            while offset < count {
                let read = Darwin.recv(fd, raw.baseAddress!.advanced(by: offset), count - offset, 0)
                if read > 0 {
                    offset += read
                    continue
                }
                if read == 0 {
                    close()
                    throw IPCError.discordClosed
                }
                if errno == EINTR { continue }
                let code = errno
                let message = errnoText()
                if code == EAGAIN || code == EWOULDBLOCK {
                    throw IPCError.timeout
                }
                close()
                if code == ECONNRESET || code == ENOTCONN || code == EBADF {
                    throw IPCError.discordClosed
                }
                throw IPCError.io("recv(): \(message)")
            }
        }
        return buffer
    }

    private func errnoText() -> String {
        String(cString: strerror(errno))
    }
}

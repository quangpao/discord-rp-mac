import Darwin
import DiscordRP
import Foundation

/// A local `AF_UNIX` server that speaks Discord's IPC protocol, so tests never need the real
/// client (and can provoke states the real one will not: bad id, hangup, silence).
final class FakeDiscordServer: @unchecked Sendable {
    let path: String
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "fake-discord-server", attributes: .concurrent)
    private let lock = NSLock()

    private var _commands: [String] = []
    private var _activities: [Any] = []
    private var _handshake: [String: Any]?
    private var _handshakes: [[String: Any]] = []
    private var _connectionActivities: [Int: [Any]] = [:]
    private var _connectionClientIDs: [Int: String] = [:]
    private var nextConnectionID = 0
    private var clientFDs: [Int32] = []

    /// When set, the handshake is answered with a CLOSE frame carrying this code/message —
    /// exactly what Discord does for an invalid Application ID.
    var reject: (code: Int, message: String)?
    var rejectNextHandshake: (code: Int, message: String)?
    var rejectedClientIDs: [String: (code: Int, message: String)] = [:]
    /// Drop the connection right after a successful handshake.
    var closeAfterHandshake = false
    var commandReplyDelay: TimeInterval = 0
    var username = "tester"

    init() {
        path = NSTemporaryDirectory()
            + "fake-discord-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8)).sock"
    }

    var commands: [String] {
        lock.lock(); defer { lock.unlock() }
        return _commands
    }

    var activities: [Any] {
        lock.lock(); defer { lock.unlock() }
        return _activities
    }

    var handshake: [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return _handshake
    }

    var handshakes: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _handshakes
    }

    var connectionActivities: [Int: [Any]] {
        lock.lock(); defer { lock.unlock() }
        return _connectionActivities
    }

    var connectionClientIDs: [Int: String] {
        lock.lock(); defer { lock.unlock() }
        return _connectionClientIDs
    }

    // MARK: lifecycle

    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENOTSOCK) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = strcpy(destination, path)
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }
        guard listen(fd, 4) == 0 else { close(fd); throw POSIXError(.EINVAL) }
        listenFD = fd

        queue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        lock.lock()
        let fds = clientFDs
        clientFDs.removeAll()
        lock.unlock()
        for fd in fds {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        unlink(path)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 { break }
            lock.lock()
            let connectionID = nextConnectionID
            nextConnectionID += 1
            clientFDs.append(client)
            lock.unlock()
            queue.async { [weak self] in
                self?.serve(client, connectionID: connectionID)
                self?.removeClient(client)
                close(client)
            }
        }
    }

    // MARK: protocol

    private func serve(_ fd: Int32, connectionID: Int) {
        while true {
            guard let (opcode, payload) = try? readFrame(fd) else { return }
            switch opcode {
            case .handshake:
                let clientID = payload["client_id"] as? String ?? ""
                lock.lock()
                _handshake = payload
                _handshakes.append(payload)
                _connectionClientIDs[connectionID] = clientID
                lock.unlock()
                let oneShotRejection: (code: Int, message: String)? = {
                    lock.lock()
                    defer { lock.unlock() }
                    let rejection = rejectNextHandshake
                    rejectNextHandshake = nil
                    return rejection
                }()
                if let reject = oneShotRejection ?? reject {
                    try? sendFrame(fd, opcode: .close, payload: ["code": reject.code, "message": reject.message])
                    return
                }
                if let rejection = rejectedClientIDs[clientID] {
                    try? sendFrame(fd, opcode: .close, payload: [
                        "code": rejection.code,
                        "message": rejection.message,
                    ])
                    return
                }
                try? sendFrame(fd, opcode: .frame, payload: [
                    "cmd": "DISPATCH", "evt": "READY",
                    "data": ["v": 1, "user": ["id": "1", "username": username]],
                ])
                if closeAfterHandshake { return }
            case .frame:
                let command = (payload["cmd"] as? String) ?? ""
                lock.lock()
                _commands.append(command)
                if command == "SET_ACTIVITY", let args = payload["args"] as? [String: Any] {
                    let activity = args["activity"] ?? NSNull()
                    _activities.append(activity)
                    _connectionActivities[connectionID, default: []].append(activity)
                }
                lock.unlock()
                if commandReplyDelay > 0 {
                    Thread.sleep(forTimeInterval: commandReplyDelay)
                }
                try? sendFrame(fd, opcode: .frame, payload: [
                    "cmd": command,
                    "nonce": (payload["nonce"] as? String) ?? "",
                    "data": NSNull(),
                ])
            case .ping:
                try? sendFrame(fd, opcode: .pong, payload: [:])
            case .pong, .close:
                return
            }
        }
    }

    private func removeClient(_ fd: Int32) {
        lock.lock()
        clientFDs.removeAll { $0 == fd }
        lock.unlock()
    }
}

// MARK: - frame IO

func sendFrame(_ fd: Int32, opcode: Opcode, payload: [String: Any]) throws {
    let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let frame = IPCProtocol.encode(opcode: opcode, body: body)
    try frame.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            if written > 0 { offset += written; continue }
            if written < 0, errno == EINTR { continue }
            throw POSIXError(.EIO)
        }
    }
}

func readFrame(_ fd: Int32) throws -> (Opcode, [String: Any]) {
    func readExact(_ count: Int) throws -> Data {
        var buffer = Data(count: count)
        var offset = 0
        try buffer.withUnsafeMutableBytes { raw in
            while offset < count {
                let got = read(fd, raw.baseAddress!.advanced(by: offset), count - offset)
                if got > 0 { offset += got; continue }
                if got == 0 { throw POSIXError(.ECONNRESET) }
                if errno == EINTR { continue }
                throw POSIXError(.EIO)
            }
        }
        return buffer
    }
    let header = try readExact(IPCProtocol.headerSize)
    let length = Int(header.loadLE(at: 4))
    let body = try readExact(length)
    return try IPCProtocol.decode(header + body)
}

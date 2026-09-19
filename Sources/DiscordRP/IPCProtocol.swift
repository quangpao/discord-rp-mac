import Foundation

/// Discord RPC-over-IPC opcodes (docs.discord.com/developers/topics/rpc).
public enum Opcode: UInt32, Sendable {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

public enum IPCError: Error, Equatable, Sendable {
    case malformedFrame(String)
    case notConnected
    case discordClosed
    /// Discord answered with `evt: ERROR` — `code` 4000 means an invalid Application ID.
    case discordRejected(code: Int, message: String)
    case timeout
    case socketUnavailable([String])
    case io(String)
}

/// Wire format: `[opcode: UInt32 LE][length: UInt32 LE][JSON body]`.
public enum IPCProtocol {
    public static let headerSize = 8
    /// Discord's own cap; frames larger than this are never legitimate here.
    public static let maxFrameSize = 1 << 20

    public static func encode(opcode: Opcode, body: Data) -> Data {
        var out = Data(capacity: headerSize + body.count)
        out.append(littleEndian: opcode.rawValue)
        out.append(littleEndian: UInt32(body.count))
        out.append(body)
        return out
    }

    /// `sortedKeys` keeps the bytes deterministic (tests assert exact output).
    public static func encode(opcode: Opcode, payload: [String: Any]) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return encode(opcode: opcode, body: body)
    }

    public static func decode(_ data: Data) throws -> (op: Opcode, payload: [String: Any]) {
        guard data.count >= headerSize else {
            throw IPCError.malformedFrame("header needs \(headerSize) bytes, got \(data.count)")
        }
        let rawOp: UInt32 = data.loadLE(at: 0)
        let length: UInt32 = data.loadLE(at: 4)
        guard let op = Opcode(rawValue: rawOp) else {
            throw IPCError.malformedFrame("unknown opcode \(rawOp)")
        }
        guard Int(length) == data.count - headerSize else {
            throw IPCError.malformedFrame("length \(length) != payload \(data.count - headerSize)")
        }
        let body = data.dropFirst(headerSize)
        let payload = body.isEmpty ? [:] : decodedJSON(Data(body))
        return (op, payload)
    }

    public static func decodedJSON(_ body: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    /// Discord reports errors either as `{"code":..,"message":..}` or as a bare string.
    public static func errorCodeAndMessage(_ data: Any?) -> (Int, String) {
        if let dict = data as? [String: Any] {
            let code = (dict["code"] as? NSNumber)?.intValue ?? 0
            let message = (dict["message"] as? String) ?? "\(dict)"
            return (code, message)
        }
        if let text = data as? String {
            return (0, text)
        }
        return (0, "unknown Discord error")
    }
}

extension Data {
    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: MemoryLayout<UInt32>.size))
    }

    public func loadLE(at offset: Int) -> UInt32 {
        withUnsafeBytes { raw in
            UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }
}

import XCTest

@testable import DiscordRP

final class IPCProtocolTests: XCTestCase {
    func testHandshakeFramingIsExact() throws {
        let frame = try IPCProtocol.encode(opcode: .handshake, payload: ["v": 1, "client_id": "123"])
        XCTAssertEqual(Array(frame.prefix(4)), [0, 0, 0, 0], "opcode 0, little-endian")
        XCTAssertEqual(frame.loadLE(at: 4), UInt32(frame.count - IPCProtocol.headerSize))
        XCTAssertEqual(
            String(decoding: frame.dropFirst(IPCProtocol.headerSize), as: UTF8.self),
            #"{"client_id":"123","v":1}"#
        )
    }

    func testDecodeRoundTrip() throws {
        let frame = try IPCProtocol.encode(opcode: .frame, payload: ["evt": "READY"])
        let (opcode, payload) = try IPCProtocol.decode(frame)
        XCTAssertEqual(opcode, .frame)
        XCTAssertEqual(payload["evt"] as? String, "READY")
    }

    func testShortHeaderIsRejected() {
        XCTAssertThrowsError(try IPCProtocol.decode(Data([0, 0, 0]))) { error in
            guard case IPCError.malformedFrame = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testLengthMismatchIsRejected() {
        var frame = Data()
        frame.append(contentsOf: [1, 0, 0, 0])
        frame.append(contentsOf: [9, 0, 0, 0])
        frame.append(contentsOf: [123, 125])
        XCTAssertThrowsError(try IPCProtocol.decode(frame))
    }

    func testUnknownOpcodeIsRejected() {
        var frame = Data()
        frame.append(contentsOf: [9, 0, 0, 0])
        frame.append(contentsOf: [2, 0, 0, 0])
        frame.append(contentsOf: [123, 125])
        XCTAssertThrowsError(try IPCProtocol.decode(frame))
    }

    func testErrorPayloadShapes() {
        let dict = IPCProtocol.errorCodeAndMessage(["code": 4000, "message": "Invalid Client ID"])
        XCTAssertEqual(dict.0, 4000)
        XCTAssertEqual(dict.1, "Invalid Client ID")
        let text = IPCProtocol.errorCodeAndMessage("something broke")
        XCTAssertEqual(text.0, 0)
        XCTAssertEqual(text.1, "something broke")
    }
}

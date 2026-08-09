import Foundation

/// gRPC length-prefixed message framing.
///
/// Every gRPC message is wrapped as:
///   [1 byte compression flag][4 byte big-endian length][message bytes]
enum GrpcFramer {
    /// Lenient base64 decoder that tolerates real-world response quirks:
    /// base64URL alphabet (`-`, `_`), stray whitespace, and `|` separators.
    ///
    /// Some gRPC-Web deployments base64-encode EACH frame separately (each chunk
    /// independently padded) and join them with `|`. Concatenating their base64
    /// text and re-padding corrupts byte alignment, so every `|`-separated chunk
    /// is decoded on its own and the raw bytes are concatenated afterwards.
    static func lenientBase64Decode(_ text: String) -> Data? {
        var result = Data()
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            var normalized = ""
            for ch in current.unicodeScalars {
                switch ch {
                case "A"..."Z", "a"..."z", "0"..."9", "+", "/":
                    normalized.unicodeScalars.append(ch)
                case "-":
                    normalized.unicodeScalars.append("+")
                case "_":
                    normalized.unicodeScalars.append("/")
                default:
                    break
                }
            }
            while normalized.count % 4 != 0 {
                normalized.append("=")
            }
            if let chunk = Data(base64Encoded: normalized) {
                result.append(chunk)
            }
            current = ""
        }
        for ch in text {
            if ch == "|" || ch == "\n" || ch == "\r" {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return result.isEmpty ? nil : result
    }

    /// Wraps a protobuf payload into a single gRPC frame (no compression).
    static func frame(_ message: Data) -> Data {
        var data = Data()
        data.append(0)
        var length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(message)
        return data
    }

    /// Splits a stream of gRPC frames into individual payloads.
    static func decodeFrames(from data: Data) throws -> [Data] {
        var result: [Data] = []
        var offset = 0
        while offset < data.count {
            guard offset + 5 <= data.count else {
                throw FiveNetError.invalidResponse("Unvollständiger gRPC-Frame (offset \(offset), count \(data.count))")
            }
            let lengthBytes = Data(data[(data.startIndex + offset + 1)..<(data.startIndex + offset + 5)])
            let length = lengthBytes.reduce(0) { ($0 << 8) | UInt32($1) }
            offset += 5
            guard offset + Int(length) <= data.count else {
                throw FiveNetError.invalidResponse("Frame-Länge \(length) übersteigt Datenende")
            }
            result.append(Data(data[(data.startIndex + offset)..<(data.startIndex + offset + Int(length))]))
            offset += Int(length)
        }
        return result
    }

    /// Parses a gRPC-Web response body (decoded from base64) into message payloads
    /// and the trailing gRPC status.
    static func parseGRPCWebResponse(_ data: Data) throws -> (messages: [Data], status: Int?, message: String?) {
        var messages: [Data] = []
        var status: Int?
        var message: String?
        var offset = 0

        while offset < data.count {
            guard offset + 5 <= data.count else {
                break
            }
            let flag = data[data.startIndex + offset]
            let lengthBytes = Data(data[(data.startIndex + offset + 1)..<(data.startIndex + offset + 5)])
            let length = lengthBytes.reduce(0) { ($0 << 8) | UInt32($1) }
            guard offset + 5 + Int(length) <= data.count else {
                // Some deployments omit the trailer frame entirely or emit a
                // trailing header block without a length prefix. Tolerate by
                // treating the remainder as a trailer/status block.
                parseTrailerBlock(Data(data[(data.startIndex + offset + 5)...]), into: &status, message: &message)
                break
            }
            offset += 5
            let payload = Data(data[(data.startIndex + offset)..<(data.startIndex + offset + Int(length))])
            offset += Int(length)

            if flag & 0x80 != 0 {
                // Trailer frame: HTTP/1.1-style header block carrying gRPC status.
                parseTrailerBlock(payload, into: &status, message: &message)
            } else {
                messages.append(payload)
            }
        }

        return (messages, status, message)
    }

    /// Parses an HTTP/1.1-style header block (with optional leading frame header)
    /// looking for `grpc-status` / `grpc-message`.
    private static func parseTrailerBlock(
        _ data: Data,
        into status: inout Int?,
        message: inout String?
    ) {
        var text = String(decoding: data, as: UTF8.self)
        // Trailer frames may carry a leading [flag][length] header — strip it.
        if data.count >= 5 {
            let flag = data[data.startIndex]
            if flag == 0x80 || flag == 0 {
                let length = Int(UInt32(data[data.startIndex + 1]) << 24 | UInt32(data[data.startIndex + 2]) << 16 | UInt32(data[data.startIndex + 3]) << 8 | UInt32(data[data.startIndex + 4]))
                if length >= 0 && length <= data.count - 5 {
                    text = String(decoding: Data(data[(data.startIndex + 5)..<(data.startIndex + 5 + length)]), as: UTF8.self)
                }
            }
        }
        for line in text.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "grpc-status":
                status = Int(value)
            case "grpc-message":
                message = value
            default:
                break
            }
        }
    }
}

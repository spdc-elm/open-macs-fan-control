import Darwin
import Foundation

package enum LocalSocket {
    package static func connect(to path: String) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw FanWriterError.daemonUnavailable(socketPath: path, reason: String(cString: strerror(errno)))
        }

        do {
            try withSocketAddress(path: path) { address, length in
                if Darwin.connect(descriptor, address, length) != 0 {
                    throw FanWriterError.daemonUnavailable(socketPath: path, reason: String(cString: strerror(errno)))
                }
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    package static func makeListener(path: String, permissions: mode_t = 0o666, backlog: Int32 = 16) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw RuntimeCommandError("failed to create daemon socket: \(String(cString: strerror(errno)))")
        }

        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        unlink(path)

        do {
            try withSocketAddress(path: path) { address, length in
                if bind(descriptor, address, length) != 0 {
                    throw RuntimeCommandError("failed to bind daemon socket at \(path): \(String(cString: strerror(errno)))")
                }
            }

            if chmod(path, permissions) != 0 {
                throw RuntimeCommandError("failed to set socket permissions at \(path): \(String(cString: strerror(errno)))")
            }

            if listen(descriptor, backlog) != 0 {
                throw RuntimeCommandError("failed to listen on daemon socket at \(path): \(String(cString: strerror(errno)))")
            }

            return descriptor
        } catch {
            close(descriptor)
            unlink(path)
            throw error
        }
    }

    package static func accept(from descriptor: Int32) throws -> Int32 {
        let clientDescriptor = Darwin.accept(descriptor, nil, nil)
        guard clientDescriptor >= 0 else {
            throw RuntimeCommandError("failed to accept daemon client: \(String(cString: strerror(errno)))")
        }
        return clientDescriptor
    }

    package static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var bytesRemaining = rawBuffer.count
            var offset = 0
            while bytesRemaining > 0 {
                let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytesRemaining)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw RuntimeCommandError("socket write failed: \(String(cString: strerror(errno)))")
                }
                bytesRemaining -= written
                offset += written
            }
        }
    }

    package static func readChunk(from descriptor: Int32, maxBytes: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        while true {
            let count = Darwin.read(descriptor, &buffer, maxBytes)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw RuntimeCommandError("socket read failed: \(String(cString: strerror(errno)))")
            }
            if count == 0 {
                return Data()
            }
            return Data(buffer.prefix(count))
        }
    }

    package static func withSocketAddress<T>(path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            throw RuntimeCommandError("socket path is too long: \(path)")
        }

        address.sun_family = sa_family_t(AF_UNIX)
#if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + MemoryLayout<UInt8>.size + pathBytes.count + 1)
#endif
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = byte
            }
        }

        let length = socklen_t(MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        return try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, length)
            }
        }
    }
}

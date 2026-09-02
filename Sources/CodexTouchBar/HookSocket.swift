import CodexTouchBarCore
import Darwin
import Foundation

enum HookSocketLocation {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexTouchBar", isDirectory: true)
    }

    static var socketURL: URL {
        supportDirectory.appendingPathComponent("status.sock", isDirectory: false)
    }
}

enum HookSocketClient {
    static func send(_ packet: HookPacket) {
        let path = HookSocketLocation.socketURL.path
        guard let address = unixAddress(path: path) else { return }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }

        var mutableAddress = address
        let result = withUnsafePointer(to: &mutableAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, let data = try? JSONEncoder().encode(packet), data.count <= 8_192 else { return }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            _ = Darwin.write(descriptor, base, bytes.count)
        }
    }
}

final class HookSocketServer {
    private let queue = DispatchQueue(label: "com.whitney.CodexTouchBar.hook-socket", qos: .utility)
    private var descriptor: Int32 = -1
    private var running = false

    func start(onPacket: @escaping (HookPacket) -> Void) throws {
        let directory = HookSocketLocation.supportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let path = HookSocketLocation.socketURL.path
        guard let address = unixAddress(path: path) else { throw SocketError.pathTooLong }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(errno) }
        var mutableAddress = address
        let bindResult = withUnsafePointer(to: &mutableAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw SocketError.system(errno)
        }
        guard chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            Darwin.close(fd)
            unlink(path)
            throw SocketError.system(errno)
        }

        descriptor = fd
        running = true
        queue.async { [weak self] in
            self?.acceptLoop(onPacket: onPacket)
        }
    }

    func stop() {
        running = false
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
        unlink(HookSocketLocation.socketURL.path)
        try? FileManager.default.removeItem(at: HookSocketLocation.supportDirectory)
    }

    deinit { stop() }

    private func acceptLoop(onPacket: @escaping (HookPacket) -> Void) {
        while running {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else {
                if running { continue }
                return
            }
            var buffer = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.read(client, &buffer, buffer.count)
            Darwin.close(client)
            guard count > 0 else { continue }
            let data = Data(buffer.prefix(Int(count)))
            guard let packet = try? JSONDecoder().decode(HookPacket.self, from: data) else { continue }
            onPacket(packet)
        }
    }

    enum SocketError: Error {
        case pathTooLong
        case system(Int32)
    }
}

private func unixAddress(path: String) -> sockaddr_un? {
    let bytes = Array(path.utf8CString)
    var address = sockaddr_un()
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else { return nil }
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.initializeMemory(as: UInt8.self, repeating: 0)
        bytes.withUnsafeBytes { source in
            destination.copyBytes(from: source)
        }
    }
    return address
}

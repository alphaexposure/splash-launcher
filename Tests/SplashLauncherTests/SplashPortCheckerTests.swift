import Darwin
import XCTest
@testable import SplashLauncher

final class SplashPortCheckerTests: XCTestCase {
    func testReportsPortInUseByLoopbackListener() throws {
        let listener = try Listener(host: "127.0.0.1")
        defer { listener.close() }
        XCTAssertNotNil(SplashPortChecker().check(configuration(port: listener.port)))
    }

    func testReportsPortInUseByListenerOnAllInterfaces() throws {
        let listener = try Listener(host: "0.0.0.0")
        defer { listener.close() }
        XCTAssertNotNil(SplashPortChecker().check(configuration(port: listener.port)))
    }

    func testAllowsPortRightAfterServerStopsWithConnectionsInTimeWait() throws {
        let listener = try Listener(host: "127.0.0.1")
        let port = listener.port
        // The server closes first, as an HTTP server does, leaving its side in TIME_WAIT.
        let client = try connectedClient(port: port)
        let accepted = Darwin.accept(listener.descriptor, nil, nil)
        XCTAssertGreaterThanOrEqual(accepted, 0)
        Darwin.close(accepted)
        usleep(50_000)
        Darwin.close(client)
        usleep(50_000)
        listener.close()
        XCTAssertNil(SplashPortChecker().check(configuration(port: port)))
    }

    func testAllowsFreePort() throws {
        let listener = try Listener(host: "127.0.0.1")
        let port = listener.port
        listener.close()
        XCTAssertNil(SplashPortChecker().check(configuration(port: port)))
    }

    private func configuration(port: Int) -> SplashConfiguration {
        var configuration = SplashConfiguration()
        configuration.host = "127.0.0.1"
        configuration.port = port
        return configuration
    }

    private func connectedClient(port: Int) throws -> Int32 {
        var address = socketAddress(host: "127.0.0.1", port: port)
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw POSIXError(.ECONNREFUSED) }
        return descriptor
    }
}

private func socketAddress(host: String, port: Int) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    inet_pton(AF_INET, host, &address.sin_addr)
    return address
}

/// A listening socket on an ephemeral port, like a running server.
private final class Listener {
    let descriptor: Int32
    let port: Int
    private var isOpen = true

    init(host: String) throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = socketAddress(host: host, port: 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else { Darwin.close(fd); throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        descriptor = fd
        port = Int(in_port_t(bigEndian: address.sin_port))
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        Darwin.close(descriptor)
    }
}

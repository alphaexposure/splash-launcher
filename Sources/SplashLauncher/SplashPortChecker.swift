import Foundation
import Darwin

protocol SplashPortChecking {
    /// Returns a user-facing error when the configured address cannot be bound.
    func check(_ configuration: SplashConfiguration) -> String?
}

struct SplashPortChecker: SplashPortChecking {
    func check(_ configuration: SplashConfiguration) -> String? {
        let host = configuration.host == "localhost" ? "127.0.0.1" : configuration.host
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(configuration.port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return "Host must be an IPv4 address or localhost."
        }
        let inUse = "Port \(configuration.port) is already in use. Choose another port or stop the other server."

        // Bind the way a server does (SO_REUSEADDR), so connections left in TIME_WAIT by a
        // server that just stopped don't count as "in use"; Splash itself can bind then.
        if let error = bindError(address) {
            return error == EADDRINUSE ? inUse
                : "Cannot bind \(configuration.host):\(configuration.port): \(String(cString: strerror(error)))."
        }

        // SO_REUSEADDR also allows binding beside a server listening on all interfaces,
        // so confirm nothing accepts connections on the port.
        if host == "0.0.0.0" { inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) }
        return acceptsConnections(address) ? inUse : nil
    }

    /// Returns errno when binding fails. The probe socket is closed before returning,
    /// so it cannot interfere with the connection check that follows.
    private func bindError(_ address: sockaddr_in) -> Int32? {
        var address = address
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return errno }
        defer { Darwin.close(descriptor) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0 ? nil : errno
    }

    private func acceptsConnections(_ address: sockaddr_in) -> Bool {
        var address = address
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

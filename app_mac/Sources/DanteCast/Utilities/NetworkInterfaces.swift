import Foundation

/// Utilitário para descobrir o IP IPv4 da LAN ativa via getifaddrs().
/// Prioriza interfaces da família "en" (en0 = Wi-Fi/Ethernet em Apple Silicon),
/// ignorando loopback, interfaces inativas e endereços de link-local.
enum NetworkInterfaces {

    /// Retorna o melhor IPv4 da LAN, ou nil se nada for encontrado.
    static func currentLANIPv4() -> String? {
        var candidates: [(name: String, ip: String)] = []

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            // Interface precisa estar UP e RUNNING, e não pode ser loopback.
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_RUNNING) == IFF_RUNNING,
                  (flags & IFF_LOOPBACK) == 0 else { continue }

            guard let addr = current.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue } // só IPv4

            let name = String(cString: current.pointee.ifa_name)

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr,
                                     socklen_t(addr.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }

            let ip = String(cString: host)
            // Ignora link-local (169.254.x.x) que não serve para LAN.
            guard !ip.hasPrefix("169.254."), !ip.hasPrefix("127.") else { continue }

            candidates.append((name, ip))
        }

        // Preferência: en0 > demais "en" > qualquer outra.
        if let en0 = candidates.first(where: { $0.name == "en0" }) { return en0.ip }
        if let en = candidates.first(where: { $0.name.hasPrefix("en") }) { return en.ip }
        return candidates.first?.ip
    }

    /// Nome amigável da máquina (host name) para exibir no pareamento.
    static func hostName() -> String {
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return name
    }
}

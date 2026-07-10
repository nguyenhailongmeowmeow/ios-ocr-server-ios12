//
//  ServerManager.swift
//  OcrServer (iOS 12 Legacy)
//
//  Singleton managing the HTTP server lifecycle. Replaces VaporServerManager.
//

import Foundation

extension Notification.Name {
    static let serverStatusDidChange = Notification.Name("serverStatusDidChange")
}

class ServerManager {
    static let shared = ServerManager()
    
    private let server = SimpleHTTPServer()
    private(set) var port: Int = Settings.shared.httpPort
    private(set) var status: String = ""
    private(set) var networkAddresses: [String: String] = [:]
    private(set) var isRunning: Bool = false
    private(set) var isRestarting: Bool = false
    
    let networkInterfaces = ["en0", "en1", "en2", "en3", "en4", "en5"]
    
    private init() {
        startServer()
    }
    
    // MARK: - Server Control
    
    func startServer() {
        setupParameters()
        
        do {
            try server.start()
            isRunning = true
            status = NSLocalizedString("server is running", comment: "")
            refreshNetworkAddresses()
        } catch {
            isRunning = false
            status = NSLocalizedString("unable to start the server", comment: "") + ": \(error.localizedDescription)"
        }
        
        postStatusNotification()
    }
    
    func stopServer() {
        server.stop()
        isRunning = false
        status = NSLocalizedString("server stopped", comment: "")
        postStatusNotification()
    }
    
    func restartServer() {
        isRestarting = true
        status = NSLocalizedString("server restarting...", comment: "")
        postStatusNotification()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.server.stop()
            
            // Brief delay before restart
            Thread.sleep(forTimeInterval: 1.0)
            
            DispatchQueue.main.async {
                self.setupParameters()
                
                do {
                    try self.server.start()
                    self.isRunning = true
                    self.status = NSLocalizedString("server is running", comment: "")
                    self.refreshNetworkAddresses()
                } catch {
                    self.isRunning = false
                    self.status = NSLocalizedString("unable to start the server", comment: "") + ": \(error.localizedDescription)"
                }
                
                self.isRestarting = false
                self.postStatusNotification()
            }
        }
    }
    
    // MARK: - Configuration
    
    private func setupParameters() {
        port = Settings.shared.httpPort
        server.port = port
        server.ocrEngine.recognitionLevel = Settings.shared.recognitionLevel
        server.ocrEngine.usesLanguageCorrection = Settings.shared.languageCorrection
        server.ocrEngine.automaticallyDetectsLanguage = Settings.shared.automaticallyDetectsLanguage
    }
    
    // MARK: - Network
    
    func refreshNetworkAddresses() {
        networkAddresses.removeAll()
        for iface in networkInterfaces {
            if let ip = getIP(for: iface) {
                networkAddresses[iface] = ip
            }
        }
        postStatusNotification()
    }
    
    private func getIP(for interface: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interfaceName = String(cString: ptr.pointee.ifa_name)
            
            if interfaceName == interface {
                let flags = Int32(ptr.pointee.ifa_flags)
                var addr = ptr.pointee.ifa_addr.pointee
                
                let isRunning = (flags & (IFF_UP|IFF_RUNNING)) == (IFF_UP|IFF_RUNNING)
                let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
                if !isRunning || isLoopback {
                    continue
                }
                
                // IPv4 only
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&addr,
                                   socklen_t(addr.sa_len),
                                   &hostname,
                                   socklen_t(hostname.count),
                                   nil, 0,
                                   NI_NUMERICHOST) == 0 {
                        return String(cString: hostname)
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Notifications
    
    private func postStatusNotification() {
        NotificationCenter.default.post(name: .serverStatusDidChange, object: self)
    }
}

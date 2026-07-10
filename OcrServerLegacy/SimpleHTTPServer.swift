//
//  SimpleHTTPServer.swift
//  OcrServer (iOS 12 Legacy)
//
//  Lightweight HTTP server using POSIX sockets + GCD. Replaces Vapor.
//

import Foundation

class SimpleHTTPServer {
    
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "httpserver.accept", qos: .userInitiated)
    private let workerQueue = DispatchQueue(label: "httpserver.worker", qos: .userInitiated, attributes: .concurrent)
    
    private(set) var isRunning = false
    var port: Int = 8000
    var ocrEngine = OCREngine()
    
    // Max upload size: 20MB
    private let maxBodySize = 20 * 1024 * 1024
    
    // MARK: - Start / Stop
    
    func start() throws {
        guard !isRunning else { return }
        
        // Create socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw ServerError.socketCreationFailed
        }
        
        // Allow address reuse
        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw ServerError.bindFailed(port: port)
        }
        
        // Listen
        guard listen(serverSocket, 128) == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw ServerError.listenFailed
        }
        
        // Set non-blocking
        let flags = fcntl(serverSocket, F_GETFL)
        fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)
        
        // Create dispatch source for accepting connections
        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        source.resume()
        acceptSource = source
        isRunning = true
    }
    
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        isRunning = false
    }
    
    // MARK: - Accept Connections
    
    private func acceptConnection() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(serverSocket, sockaddrPtr, &addrLen)
            }
        }
        
        guard clientSocket >= 0 else { return }
        
        workerQueue.async { [weak self] in
            self?.handleConnection(clientSocket)
        }
    }
    
    // MARK: - Handle Connection
    
    private func handleConnection(_ clientSocket: Int32) {
        defer { close(clientSocket) }
        
        // Read request (headers + body)
        guard let requestData = readHTTPRequest(from: clientSocket) else {
            sendResponse(to: clientSocket, status: 400, contentType: "text/plain", body: "Bad Request")
            return
        }
        
        guard let headerEnd = requestData.range(of: Data("\r\n\r\n".utf8)) else {
            sendResponse(to: clientSocket, status: 400, contentType: "text/plain", body: "Bad Request")
            return
        }
        
        let headerData = requestData.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            sendResponse(to: clientSocket, status: 400, contentType: "text/plain", body: "Bad Request")
            return
        }
        
        let bodyData = requestData.subdata(in: headerEnd.upperBound..<requestData.count)
        
        // Parse first line
        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(to: clientSocket, status: 400, contentType: "text/plain", body: "Bad Request")
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(to: clientSocket, status: 400, contentType: "text/plain", body: "Bad Request")
            return
        }
        
        let method = parts[0].uppercased()
        let path = parts[1]
        
        // Parse headers into dictionary
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonRange = line.range(of: ":") {
                let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        // Read remaining body if Content-Length indicates more data
        var fullBody = bodyData
        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr),
           contentLength > 0 {
            
            guard contentLength <= maxBodySize else {
                sendResponse(to: clientSocket, status: 413, contentType: "text/plain", body: "Request body too large")
                return
            }
            
            while fullBody.count < contentLength {
                let remaining = contentLength - fullBody.count
                let bufSize = min(remaining, 65536)
                var buf = [UInt8](repeating: 0, count: bufSize)
                let n = recv(clientSocket, &buf, bufSize, 0)
                if n <= 0 { break }
                fullBody.append(contentsOf: buf[0..<n])
            }
        }
        
        // Route
        let accept = headers["accept"] ?? ""
        
        switch (method, path) {
        case ("GET", "/"):
            handleGetRoot(clientSocket: clientSocket)
        case ("POST", "/upload"):
            handleUpload(clientSocket: clientSocket, headers: headers, body: fullBody, accept: accept)
        case ("POST", "/docOCR"):
            handleDocOCR(clientSocket: clientSocket, headers: headers, body: fullBody, accept: accept)
        default:
            sendResponse(to: clientSocket, status: 404, contentType: "text/plain", body: "Not Found")
        }
    }
    
    // MARK: - Read HTTP Request
    
    private func readHTTPRequest(from socket: Int32) -> Data? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        
        // Set a read timeout
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // Read until we have the headers
        while true {
            let n = recv(socket, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            
            // Check if we've received the end of headers
            if data.range(of: Data("\r\n\r\n".utf8)) != nil {
                break
            }
            
            // Safety limit for headers
            if data.count > 1024 * 1024 { break }
        }
        
        return data.isEmpty ? nil : data
    }
    
    // MARK: - Route Handlers
    
    private func handleGetRoot(clientSocket: Int32) {
        let html = """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>OCR Server</title>
            <style>
                body { font-family: -apple-system, sans-serif; padding: 20px; }
                code {
                    background: #dadada; padding: 2px 6px;
                    font-family: 'SFMono-Regular', Consolas, monospace;
                    font-size: 0.85em; font-weight: 600; border-radius: 5px;
                }
                pre {
                    background: #dadada; padding: 16px; overflow: auto;
                    font-family: 'SFMono-Regular', Consolas, monospace;
                    font-size: 0.85em; line-height: 1.45; border-radius: 5px;
                }
                pre code { background: transparent; padding: 0; font-weight: normal; }
            </style>
        </head>
        <body>
            <h1>OCR Server</h1>
            <h3>Upload an image via <code>upload</code> API:</h3>
            <pre><code>curl -H "Accept: application/json" \\
          -X POST http://&lt;YOUR IP&gt;:\(port)/upload \\
          -F "file=@01.png"</code></pre>
            <hr>
            <h3>OCR Test:</h3>
            <form id="ocrForm" action="/upload" method="post" enctype="multipart/form-data">
                <label>
                    Choose file:
                    <input type="file" name="file" required>
                </label>
                <br><br>
                <input type="submit" value="Upload file">
            </form>
        </body>
        </html>
        """
        sendResponse(to: clientSocket, status: 200, contentType: "text/html; charset=utf-8", body: html)
    }
    
    private func handleUpload(clientSocket: Int32, headers: [String: String], body: Data, accept: String) {
        // Extract file data from multipart/form-data
        guard let fileData = extractFileData(from: body, headers: headers) else {
            let response = UploadResponse(
                success: false,
                message: "Missing or empty 'file' part",
                ocr_result: "",
                image_width: 0,
                image_height: 0,
                ocr_boxes: []
            )
            sendJSONResponse(to: clientSocket, status: 400, response: response)
            return
        }
        
        // Perform OCR (synchronous wait via semaphore for this connection)
        let semaphore = DispatchSemaphore(value: 0)
        var ocrResponse: UploadResponse?
        
        ocrEngine.recognizeText(from: fileData) { result in
            ocrResponse = result
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 120) // 2 minute timeout
        
        guard let result = ocrResponse else {
            let response = UploadResponse(
                success: false,
                message: "OCR timeout",
                ocr_result: "",
                image_width: 0,
                image_height: 0,
                ocr_boxes: []
            )
            sendJSONResponse(to: clientSocket, status: 500, response: response)
            return
        }
        
        if accept.lowercased().contains("application/json") {
            sendJSONResponse(to: clientSocket, status: result.success ? 200 : 500, response: result)
        } else {
            // Return HTML result
            let escaped = htmlEscape(result.ocr_result)
            let html = """
            <!doctype html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>OCR Server</title>
            </head>
            <body>
                <h2>OCR Result:</h2>
                <pre>\(escaped)</pre>
            </body>
            </html>
            """
            sendResponse(to: clientSocket, status: 200, contentType: "text/html; charset=utf-8", body: html)
        }
    }
    
    private func handleDocOCR(clientSocket: Int32, headers: [String: String], body: Data, accept: String) {
        // docOCR is only for iOS 26+ in original; return not supported
        let response = UploadResponse(
            success: false,
            message: "docOCR API is not supported in this legacy version",
            ocr_result: "",
            image_width: 0,
            image_height: 0,
            ocr_boxes: []
        )
        sendJSONResponse(to: clientSocket, status: 200, response: response)
    }
    
    // MARK: - Multipart Parser
    
    private func extractFileData(from body: Data, headers: [String: String]) -> Data? {
        guard let contentType = headers["content-type"],
              contentType.contains("multipart/form-data") else {
            return nil
        }
        
        // Extract boundary
        guard let boundaryRange = contentType.range(of: "boundary=") else { return nil }
        var boundary = String(contentType[boundaryRange.upperBound...])
        // Remove any trailing parameters or quotes
        if boundary.hasPrefix("\"") {
            boundary = String(boundary.dropFirst())
            if let endQuote = boundary.firstIndex(of: "\"") {
                boundary = String(boundary[boundary.startIndex..<endQuote])
            }
        }
        if let semicolonIdx = boundary.firstIndex(of: ";") {
            boundary = String(boundary[boundary.startIndex..<semicolonIdx])
        }
        boundary = boundary.trimmingCharacters(in: .whitespaces)
        
        let boundaryData = Data("--\(boundary)".utf8)
        let doubleCRLF = Data("\r\n\r\n".utf8)
        
        // Find file part
        var searchRange = body.startIndex..<body.endIndex
        
        while let partStart = body.range(of: boundaryData, in: searchRange) {
            let afterBoundary = partStart.upperBound
            guard afterBoundary < body.endIndex else { break }
            
            // Find the headers section of this part
            guard let headerEnd = body.range(of: doubleCRLF, in: afterBoundary..<body.endIndex) else { break }
            
            let partHeaderData = body.subdata(in: afterBoundary..<headerEnd.lowerBound)
            let partHeaders = String(data: partHeaderData, encoding: .utf8) ?? ""
            
            // Check if this part contains a file (has filename in Content-Disposition)
            if partHeaders.contains("filename=") || partHeaders.contains("name=\"file\"") {
                // Find the end of this part (next boundary)
                let contentStart = headerEnd.upperBound
                let nextBoundary = body.range(of: Data("\r\n--\(boundary)".utf8), in: contentStart..<body.endIndex)
                let contentEnd = nextBoundary?.lowerBound ?? body.endIndex
                
                let fileData = body.subdata(in: contentStart..<contentEnd)
                if fileData.count > 0 {
                    return fileData
                }
            }
            
            searchRange = afterBoundary..<body.endIndex
        }
        
        return nil
    }
    
    // MARK: - Response Helpers
    
    private func sendResponse(to socket: Int32, status: Int, contentType: String, body: String) {
        let bodyData = Data(body.utf8)
        let statusText = httpStatusText(status)
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        
        var response = Data(header.utf8)
        response.append(bodyData)
        
        response.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            var sent = 0
            while sent < response.count {
                let n = send(socket, baseAddress.advanced(by: sent), response.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
    
    private func sendJSONResponse(to socket: Int32, status: Int, response: UploadResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let jsonData = try? encoder.encode(response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendResponse(to: socket, status: 500, contentType: "text/plain", body: "JSON encoding error")
            return
        }
        sendResponse(to: socket, status: status, contentType: "application/json; charset=utf-8", body: jsonString)
    }
    
    private func htmlEscape(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    private func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
    
    // MARK: - Errors
    
    enum ServerError: Error, LocalizedError {
        case socketCreationFailed
        case bindFailed(port: Int)
        case listenFailed
        
        var errorDescription: String? {
            switch self {
            case .socketCreationFailed: return "Failed to create socket"
            case .bindFailed(let port): return "Failed to bind to port \(port)"
            case .listenFailed: return "Failed to listen on socket"
            }
        }
    }
}

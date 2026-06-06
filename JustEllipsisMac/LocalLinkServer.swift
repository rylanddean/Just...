// LocalLinkServer.swift — JustEllipsisMac
// Runs a minimal HTTP server on localhost:21471 so the Safari web extension
// can POST links without requiring the nativeMessaging manifest permission
// (which Safari on macOS 26 rejects at load time).

import Foundation
import Network
import os.log

private let serverLog = Logger(
    subsystem: "com.rylandean.justellipsis.mac",
    category: "localserver"
)

final class LocalLinkServer: @unchecked Sendable {

    static let port: UInt16 = 21471

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.rylandean.justellipsis.localserver",
                                      qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: Self.port) else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            serverLog.error("Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                serverLog.info("LocalLinkServer listening on port \(LocalLinkServer.port)")
            case .failed(let error):
                serverLog.error("LocalLinkServer failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        accumulate(Data(), on: connection)
    }

    /// Reads chunks until we have a complete HTTP request (headers + full body),
    /// then hands off to processRequest. This prevents "malformed body" errors
    /// when the POST body arrives in a separate TCP segment from the headers.
    private func accumulate(_ buffer: Data, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, _, error in
            guard let self else { return }
            guard let chunk, error == nil else {
                connection.cancel()
                return
            }

            let accumulated = buffer + chunk

            if self.isCompleteHTTPRequest(accumulated) {
                self.processRequest(data: accumulated, connection: connection)
            } else {
                self.accumulate(accumulated, on: connection)
            }
        }
    }

    /// Returns true once we hold at least as many bytes as the Content-Length header specifies.
    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8),
              let separatorRange = raw.range(of: "\r\n\r\n") else {
            return false     // headers not yet complete
        }

        // If there's a Content-Length, wait until the body is fully buffered.
        if let clRange = raw.range(of: "Content-Length: ",
                                   options: .caseInsensitive,
                                   range: raw.startIndex..<separatorRange.lowerBound),
           let eol = raw[clRange.upperBound...].range(of: "\r\n"),
           let contentLength = Int(raw[clRange.upperBound..<eol.lowerBound]) {
            let headerByteCount = raw[..<separatorRange.upperBound]
                .utf8.count          // bytes up to and including the blank line
            return data.count >= headerByteCount + contentLength
        }

        return true     // no Content-Length → treat as complete (e.g. OPTIONS)
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let raw = String(data: data, encoding: .utf8) else {
            send("{\"result\":\"error\"}", to: connection)
            return
        }

        // CORS preflight
        if raw.hasPrefix("OPTIONS") {
            send("", status: "204 No Content", to: connection)
            return
        }

        // Extract JSON body after the blank line separating headers from body
        guard
            let separatorRange = raw.range(of: "\r\n\r\n"),
            let bodyData = String(raw[separatorRange.upperBound...]).data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let url = json["url"] as? String
        else {
            serverLog.error("processRequest: malformed body — \(data.count) bytes, preview: \(raw.prefix(300))")
            send("{\"result\":\"error\"}", to: connection)
            return
        }

        let title = json["title"] as? String
        serverLog.info("processRequest: saving '\(url)'")

        Task {
            let result = await CloudKitLinkWriter.save(url: url, title: title)
            self.send("{\"result\":\"\(result)\"}", to: connection)
        }
    }

    // MARK: - HTTP helpers

    private func send(_ body: String,
                      status: String = "200 OK",
                      to connection: NWConnection) {
        let bodyBytes = body.data(using: .utf8) ?? Data()
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json",
            "Content-Length: \(bodyBytes.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Access-Control-Allow-Private-Network: true",   // CORS-RFC1918 / Private Network Access
            "Connection: close",
            "", ""                      // blank line ends headers
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(bodyBytes)

        // isComplete: true sends a TCP FIN after the response so the remote
        // reads all data before the connection closes (avoids RST truncation).
        connection.send(content: response,
                        contentContext: .finalMessage,
                        isComplete: true,
                        completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

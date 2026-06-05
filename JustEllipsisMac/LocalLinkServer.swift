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

final class LocalLinkServer {

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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            self.processRequest(data: data, connection: connection)
        }
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
            serverLog.error("processRequest: malformed body in request")
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
            "Connection: close",
            "", ""                      // blank line ends headers
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(bodyBytes)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

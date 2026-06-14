//
//  RideControlServer.swift
//  Blind Spot
//
//  A tiny local HTTP/1.1 server (Network.framework / NWListener) that lets the
//  Raspberry Pi start/stop a ride over the iPhone's Personal Hotspot LAN.
//  Listens on port 8787 while the ride screen is active.
//
//  Endpoints:
//    POST /blindspot/ride/start  -> { ok, ride_id, status: "recording" }
//    POST /blindspot/ride/stop   -> { ok, ride_id, status: "stopped" }
//
//  The phone owns all GPS/route tracking + Supabase writes; the Pi only triggers
//  start/stop and uses the returned ride_id to attach its photos.
//
//  Requires NSLocalNetworkUsageDescription (the OS prompts on first listen).
//

import Foundation
import Network

/// What the server calls into to actually start/stop a ride. Implemented by
/// RideController. `@MainActor` because it mutates app/UI state.
@MainActor
protocol RideControlDelegate: AnyObject {
    func rideControlStart() async -> UUID?
    func rideControlStop(rideId: UUID?) async -> Bool
    /// The active ride id, or nil when idle. Used for status queries.
    var activeRideId: UUID? { get }
    /// "recording" while a ride is active, otherwise "idle".
    var rideStatusString: String { get }
}

final class RideControlServer {

    static let port: NWEndpoint.Port = 8787

    weak var delegate: RideControlDelegate?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.ronakrupani.blindspot.ridecontrol")

    // MARK: Lifecycle

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: Self.port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            // Listener couldn't bind (e.g. port busy). The HTTP fallback path on
            // the Pi side / a retry would handle this; we just log.
            print("[RideControlServer] failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, buffer: Data())
    }

    /// Accumulate bytes until a full HTTP request (headers + Content-Length body)
    /// is available, then route it.
    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest.parse(buffer) {
                self.route(request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.readRequest(connection, buffer: buffer)   // need more bytes
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        // Ride start/stop are async + main-actor isolated; hop over, then reply.
        Task { @MainActor in
            let (status, json) = await self.handle(request)
            self.respond(status: status, json: json, on: connection)
        }
    }

    @MainActor
    private func handle(_ request: HTTPRequest) async -> (Int, [String: Any]) {
        guard request.method == "POST" else {
            return (405, ["ok": false, "error": "method not allowed"])
        }

        switch request.path {
        case "/blindspot/ride/start":
            if let id = await delegate?.rideControlStart() {
                return (200, ["ok": true, "ride_id": id.uuidString, "status": "recording"])
            }
            return (500, ["ok": false, "error": "could not start ride"])

        case "/blindspot/ride/stop":
            let rideId = (request.json?["ride_id"] as? String).flatMap(UUID.init(uuidString:))
            let ok = await delegate?.rideControlStop(rideId: rideId) ?? false
            if ok {
                return (200, ["ok": true,
                              "ride_id": rideId?.uuidString as Any,
                              "status": "stopped"])
            }
            return (409, ["ok": false, "error": "no matching active ride"])

        default:
            return (404, ["ok": false, "error": "unknown endpoint"])
        }
    }

    private func respond(status: Int, json: [String: Any], on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        default:  return "Internal Server Error"
        }
    }
}

// MARK: - Minimal HTTP request parser

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    var json: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// Returns a request only when the full headers + Content-Length body are
    /// present; otherwise nil (caller keeps reading).
    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else { return nil }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= contentLength else { return nil }   // body not fully read

        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        let body = data.subdata(in: bodyStart..<bodyEnd)

        return HTTPRequest(method: String(tokens[0]),
                           path: String(tokens[1]),
                           headers: headers,
                           body: body)
    }
}

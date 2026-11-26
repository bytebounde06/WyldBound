import Foundation
import Network
import WebKit

/// Nearby trading on the same Wi-Fi, compatible with the Android app.
/// Both apps announce a Bonjour service "_wyldtrade._tcp" and talk over a plain TCP
/// connection using one JSON message per line:
///   {"op":"invite","name":...}  {"op":"accept"}  {"op":"decline"}  {"op":"data","data":...}
/// No internet or server involved.
///
/// JavaScript → native:  window.webkit.messageHandlers.wbPeer.postMessage({op: ...})
///   start {name}, stop, invite {id}, answer {id, ok}, send {data}
/// Native → JavaScript:  window.WBPeerEvent({type: ...})
///   peers {list:[{id,name}]}, invite {id,name}, connected {name}, disconnected {name}, data {data}, error {message}
final class PeerLink: NSObject, WKScriptMessageHandler {
    static let serviceType = "_wyldtrade._tcp"
    weak var webView: WKWebView?

    private let queue = DispatchQueue(label: "wyld.peer")
    private var myName = ""
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var found: [String: NWEndpoint] = [:]
    private var conn: NWConnection?            // the active trade connection
    private var connName = ""
    private var pending: [String: NWConnection] = [:]   // incoming invites waiting for an answer
    private var buffers: [ObjectIdentifier: Data] = [:]

    // MARK: JavaScript messages
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        queue.async {
            switch op {
            case "start": self.start(name: (body["name"] as? String) ?? "Trainer")
            case "stop": self.stop()
            case "invite": if let id = body["id"] as? String { self.invite(id) }
            case "answer": if let id = body["id"] as? String { self.answer(id, ok: (body["ok"] as? Bool) ?? false) }
            case "send": if let d = body["data"] as? String { self.sendLine(["op": "data", "data": d], on: self.conn) }
            default: break
            }
        }
    }

    // MARK: Start / stop
    private func start(name: String) {
        stop()
        myName = String(name.prefix(20)) + " #" + String(Int.random(in: 100...999))
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: myName, type: PeerLink.serviceType)
            l.newConnectionHandler = { [weak self] c in self?.incoming(c) }
            l.stateUpdateHandler = { [weak self] st in if case .failed(let e) = st { self?.emit(["type": "error", "message": "\(e)"]) } }
            l.start(queue: queue)
            listener = l
        } catch { emit(["type": "error", "message": "\(error)"]) }
        let b = NWBrowser(for: .bonjour(type: PeerLink.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            self.found.removeAll()
            for r in results {
                if case let .service(name, _, _, _) = r.endpoint, name != self.myName { self.found[name] = r.endpoint }
            }
            self.emitPeers()
        }
        b.start(queue: queue)
        browser = b
        emitPeers()
    }

    private func stop() {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        conn?.cancel(); conn = nil
        pending.values.forEach { $0.cancel() }; pending.removeAll()
        found.removeAll(); buffers.removeAll()
    }

    // MARK: Connections
    private func invite(_ id: String) {
        guard let ep = found[id] else { return }
        let c = NWConnection(to: ep, using: .tcp)
        setup(c, outgoing: true, name: id)
        c.start(queue: queue)
    }

    private func incoming(_ c: NWConnection) {
        setup(c, outgoing: false, name: "")
        c.start(queue: queue)
    }

    private func setup(_ c: NWConnection, outgoing: Bool, name: String) {
        c.stateUpdateHandler = { [weak self, weak c] st in
            guard let self = self, let c = c else { return }
            switch st {
            case .ready:
                self.receive(on: c)
                if outgoing { self.conn = c; self.connName = name; self.sendLine(["op": "invite", "name": self.myName], on: c) }
            case .failed, .cancelled:
                if c === self.conn { self.conn = nil; self.emit(["type": "disconnected", "name": self.connName]) }
            default: break
            }
        }
    }

    private func answer(_ id: String, ok: Bool) {
        guard let c = pending.removeValue(forKey: id) else { return }
        if ok {
            conn = c; connName = id
            sendLine(["op": "accept"], on: c)
            emit(["type": "connected", "name": id])
        } else {
            sendLine(["op": "decline"], on: c)
            queue.asyncAfter(deadline: .now() + 0.5) { c.cancel() }
        }
    }

    private func receive(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak c] data, _, done, err in
            guard let self = self, let c = c else { return }
            if let data = data, !data.isEmpty {
                let key = ObjectIdentifier(c)
                var buf = (self.buffers[key] ?? Data()) + data
                while let nl = buf.firstIndex(of: 10) {
                    let line = buf.subdata(in: buf.startIndex..<nl)
                    buf.removeSubrange(buf.startIndex...nl)
                    self.handle(line, from: c)
                }
                self.buffers[key] = buf
            }
            if done || err != nil {
                if c === self.conn { self.conn = nil; self.emit(["type": "disconnected", "name": self.connName]) }
                c.cancel(); return
            }
            self.receive(on: c)
        }
    }

    private func handle(_ line: Data, from c: NWConnection) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let op = obj["op"] as? String else { return }
        switch op {
        case "invite":
            let n = (obj["name"] as? String) ?? "Trainer"
            pending[n] = c
            emit(["type": "invite", "id": n, "name": n])
        case "accept":
            if c === conn { emit(["type": "connected", "name": connName]) }
        case "decline":
            if c === conn { conn = nil; emit(["type": "error", "message": "\(connName) declined."]) }
            c.cancel()
        case "data":
            if c === conn, let d = obj["data"] as? String { emit(["type": "data", "data": d]) }
        default: break
        }
    }

    private func sendLine(_ obj: [String: Any], on c: NWConnection?) {
        guard let c = c, var d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        d.append(10)
        c.send(content: d, completion: .contentProcessed { [weak self] e in if let e = e { self?.emit(["type": "error", "message": "\(e)"]) } })
    }

    // MARK: Events to the game
    private func emit(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { self.webView?.evaluateJavaScript("window.WBPeerEvent && window.WBPeerEvent(\(json));", completionHandler: nil) }
    }
    private func emitPeers() { emit(["type": "peers", "list": found.keys.sorted().map { ["id": $0, "name": $0] }]) }
}

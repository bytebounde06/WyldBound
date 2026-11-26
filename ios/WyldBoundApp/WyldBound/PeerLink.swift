import Foundation
import MultipeerConnectivity
import WebKit

/// Nearby trading: finds other phones running WyldBound on the same Wi-Fi (or nearby over
/// peer-to-peer Wi-Fi/Bluetooth) using Apple's Multipeer Connectivity, and passes small
/// trade messages between the two games. No internet or server involved.
///
/// JavaScript → native:  window.webkit.messageHandlers.wbPeer.postMessage({op: ...})
///   start {name}, stop, invite {id}, answer {id, ok}, send {data}
/// Native → JavaScript:  window.WBPeerEvent({type: ...})
///   peers {list:[{id,name}]}, invite {id,name}, connected {name}, disconnected, data {data}, error {message}
final class PeerLink: NSObject, WKScriptMessageHandler, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let serviceType = "wyldtrade"
    weak var webView: WKWebView?

    private var myPeer: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var found: [String: MCPeerID] = [:]
    private var pendingInvites: [String: (Bool, MCSession?) -> Void] = [:]
    private var inviteFrom: [String: MCPeerID] = [:]

    // MARK: JavaScript messages
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        DispatchQueue.main.async {
            switch op {
            case "start": self.start(name: (body["name"] as? String) ?? "Trainer")
            case "stop": self.stop()
            case "invite": if let id = body["id"] as? String { self.invite(id) }
            case "answer": if let id = body["id"] as? String { self.answer(id, ok: (body["ok"] as? Bool) ?? false) }
            case "send": if let data = body["data"] as? String { self.send(data) }
            default: break
            }
        }
    }

    private func start(name: String) {
        stop()
        let clean = String(name.prefix(20)) + " #" + String(Int.random(in: 100...999))
        let peer = MCPeerID(displayName: clean)
        myPeer = peer
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: PeerLink.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        let br = MCNearbyServiceBrowser(peer: peer, serviceType: PeerLink.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
        emitPeers()
    }

    private func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil; browser = nil; session = nil; myPeer = nil
        found.removeAll(); pendingInvites.removeAll(); inviteFrom.removeAll()
    }

    private func invite(_ id: String) {
        guard let peer = found[id], let s = session else { return }
        browser?.invitePeer(peer, to: s, withContext: nil, timeout: 30)
    }

    private func answer(_ id: String, ok: Bool) {
        guard let handler = pendingInvites.removeValue(forKey: id) else { return }
        handler(ok, ok ? session : nil)
    }

    private func send(_ text: String) {
        guard let s = session, !s.connectedPeers.isEmpty, let d = text.data(using: .utf8) else { return }
        do { try s.send(d, toPeers: s.connectedPeers, with: .reliable) }
        catch { emit(["type": "error", "message": error.localizedDescription]) }
    }

    // MARK: Sending events to the game
    private func emit(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.WBPeerEvent && window.WBPeerEvent(\(json));", completionHandler: nil)
        }
    }
    private func emitPeers() {
        let list = found.map { ["id": $0.key, "name": $0.value.displayName] }
        emit(["type": "peers", "list": list])
    }

    // MARK: Browser
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { self.found[peerID.displayName] = peerID; self.emitPeers() }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.found.removeValue(forKey: peerID.displayName); self.emitPeers() }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        emit(["type": "error", "message": error.localizedDescription])
    }

    // MARK: Advertiser
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            self.pendingInvites[peerID.displayName] = invitationHandler
            self.emit(["type": "invite", "id": peerID.displayName, "name": peerID.displayName])
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        emit(["type": "error", "message": error.localizedDescription])
    }

    // MARK: Session
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: emit(["type": "connected", "name": peerID.displayName])
        case .notConnected: emit(["type": "disconnected", "name": peerID.displayName])
        default: break
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let text = String(data: data, encoding: .utf8) { emit(["type": "data", "data": text]) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

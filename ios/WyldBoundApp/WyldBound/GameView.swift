import SwiftUI
import WebKit

/// Hosts the game (WyldBound.html, bundled inside the app) in a full-screen web view.
/// Everything runs offline on the device.
struct GameView: UIViewRepresentable {
    final class Coordinator {
        let store = SaveStore()
        let peer = PeerLink()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let store = context.coordinator.store
        let peer = context.coordinator.peer
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Save files are mirrored into the app's Documents folder (wyldbound_saves.json)
        // so they survive even if iOS clears web storage. They are injected at launch.
        let ucc = WKUserContentController()
        ucc.add(store, name: "wbStore")
        ucc.add(peer, name: "wbPeer")   // nearby trading (Multipeer Connectivity)
        let boot = "window.WB_NATIVE_STORE = \(store.jsonString());"
        ucc.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.23, green: 0.18, blue: 0.43, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) { web.isInspectable = true }
        peer.webView = web

        if let url = Bundle.main.url(forResource: "WyldBound", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Receives save writes from the game and stores them on disk.
final class SaveStore: NSObject, WKScriptMessageHandler {
    private var data: [String: String] = [:]
    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("wyldbound_saves.json")
    }()

    override init() {
        super.init()
        if let d = try? Data(contentsOf: fileURL),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
            data = obj
        }
    }

    func jsonString() -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: data),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String,
              let key = body["k"] as? String else { return }
        if op == "set", let value = body["v"] as? String {
            data[key] = value
        } else if op == "del" {
            data.removeValue(forKey: key)
        }
        if let d = try? JSONSerialization.data(withJSONObject: data) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }
}

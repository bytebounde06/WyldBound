package com.wyldbound.game;

import android.app.Activity;
import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Nearby trading on the same Wi-Fi, compatible with the iPhone app.
 * Announces/finds the Bonjour (mDNS) service "_wyldtrade._tcp" and talks over plain TCP,
 * one JSON message per line: invite / accept / decline / data.
 * The game calls window.AndroidPeer.start(name), stop(), invite(id), answer(id, ok), send(data)
 * and receives events through window.WBPeerEvent({...}).
 */
public class PeerBridge {
    private static final String TYPE = "_wyldtrade._tcp.";
    private final Activity act;
    private final WebView web;
    private final NsdManager nsd;
    private final ExecutorService io = Executors.newCachedThreadPool();
    private WifiManager.MulticastLock lock;
    private ServerSocket server;
    private NsdManager.RegistrationListener regListener;
    private NsdManager.DiscoveryListener discListener;
    private String myName = "";
    private final Map<String, NsdServiceInfo> found = new HashMap<>();
    private final Map<String, Socket> pending = new HashMap<>();
    private Socket conn;
    private String connName = "";

    public PeerBridge(Activity act, WebView web) {
        this.act = act; this.web = web;
        this.nsd = (NsdManager) act.getSystemService(Context.NSD_SERVICE);
    }

    // ---------- events to the game ----------
    private void emit(JSONObject o) {
        final String js = "window.WBPeerEvent && window.WBPeerEvent(" + o.toString() + ");";
        act.runOnUiThread(() -> web.evaluateJavascript(js, null));
    }
    private void emit(String type, String k1, String v1) {
        try { JSONObject o = new JSONObject(); o.put("type", type); if (k1 != null) o.put(k1, v1); emit(o); } catch (Exception ignored) {}
    }
    private synchronized void emitPeers() {
        try {
            JSONArray list = new JSONArray();
            for (String n : found.keySet()) { JSONObject p = new JSONObject(); p.put("id", n); p.put("name", n); list.put(p); }
            JSONObject o = new JSONObject(); o.put("type", "peers"); o.put("list", list); emit(o);
        } catch (Exception ignored) {}
    }

    // ---------- calls from the game ----------
    @JavascriptInterface public void start(String name) {
        stop();
        myName = (name.length() > 20 ? name.substring(0, 20) : name) + " #" + (100 + new Random().nextInt(900));
        WifiManager wifi = (WifiManager) act.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi != null) { lock = wifi.createMulticastLock("wyldtrade"); lock.setReferenceCounted(false); lock.acquire(); }
        io.execute(() -> {
            try {
                server = new ServerSocket(0);
                NsdServiceInfo info = new NsdServiceInfo();
                info.setServiceName(myName); info.setServiceType(TYPE); info.setPort(server.getLocalPort());
                regListener = new NsdManager.RegistrationListener() {
                    public void onServiceRegistered(NsdServiceInfo i) { myName = i.getServiceName(); }
                    public void onRegistrationFailed(NsdServiceInfo i, int e) { emit("error", "message", "Couldn't announce this phone (" + e + ")."); }
                    public void onServiceUnregistered(NsdServiceInfo i) {}
                    public void onUnregistrationFailed(NsdServiceInfo i, int e) {}
                };
                nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, regListener);
                final ServerSocket s = server;
                while (!s.isClosed()) { Socket c = s.accept(); readLoop(c); }
            } catch (Exception ignored) {}
        });
        discListener = new NsdManager.DiscoveryListener() {
            public void onDiscoveryStarted(String t) {}
            public void onDiscoveryStopped(String t) {}
            public void onStartDiscoveryFailed(String t, int e) { emit("error", "message", "Couldn't search for nearby phones (" + e + ")."); }
            public void onStopDiscoveryFailed(String t, int e) {}
            public void onServiceFound(NsdServiceInfo i) {
                if (i.getServiceName().equals(myName)) return;
                synchronized (PeerBridge.this) { found.put(i.getServiceName(), i); }
                emitPeers();
            }
            public void onServiceLost(NsdServiceInfo i) {
                synchronized (PeerBridge.this) { found.remove(i.getServiceName()); }
                emitPeers();
            }
        };
        nsd.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, discListener);
        emitPeers();
    }

    @JavascriptInterface public void stop() {
        try { if (discListener != null) nsd.stopServiceDiscovery(discListener); } catch (Exception ignored) {}
        try { if (regListener != null) nsd.unregisterService(regListener); } catch (Exception ignored) {}
        discListener = null; regListener = null;
        try { if (server != null) server.close(); } catch (Exception ignored) {}
        server = null;
        closeQuiet(conn); conn = null;
        synchronized (this) { for (Socket s : pending.values()) closeQuiet(s); pending.clear(); found.clear(); }
        if (lock != null) { try { lock.release(); } catch (Exception ignored) {} lock = null; }
    }

    @JavascriptInterface public void invite(final String id) {
        final NsdServiceInfo info;
        synchronized (this) { info = found.get(id); }
        if (info == null) return;
        nsd.resolveService(info, new NsdManager.ResolveListener() {
            public void onResolveFailed(NsdServiceInfo i, int e) { emit("error", "message", "Couldn't reach " + id + " (" + e + ")."); }
            public void onServiceResolved(final NsdServiceInfo i) {
                io.execute(() -> {
                    try {
                        InetAddress host = i.getHost();
                        Socket c = new Socket(host, i.getPort());
                        conn = c; connName = id;
                        sendLine(c, new JSONObject().put("op", "invite").put("name", myName));
                        readLoop(c);
                    } catch (Exception e) { emit("error", "message", "Couldn't connect to " + id + "."); }
                });
            }
        });
    }

    @JavascriptInterface public void answer(String id, boolean ok) {
        final Socket c;
        synchronized (this) { c = pending.remove(id); }
        if (c == null) return;
        io.execute(() -> {
            try {
                if (ok) { conn = c; connName = id; sendLine(c, new JSONObject().put("op", "accept")); emit("connected", "name", id); }
                else { sendLine(c, new JSONObject().put("op", "decline")); Thread.sleep(400); closeQuiet(c); }
            } catch (Exception ignored) {}
        });
    }

    @JavascriptInterface public void send(final String data) {
        final Socket c = conn;
        if (c == null) return;
        io.execute(() -> { try { sendLine(c, new JSONObject().put("op", "data").put("data", data)); } catch (Exception e) { emit("error", "message", "Send failed."); } });
    }

    // ---------- wire ----------
    private void readLoop(final Socket c) {
        io.execute(() -> {
            try (BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) handle(line, c);
            } catch (Exception ignored) {}
            if (c == conn) { conn = null; emit("disconnected", "name", connName); }
            closeQuiet(c);
        });
    }

    private void handle(String line, Socket c) {
        try {
            JSONObject o = new JSONObject(line);
            String op = o.optString("op");
            if (op.equals("invite")) {
                String n = o.optString("name", "Trainer");
                synchronized (this) { pending.put(n, c); }
                JSONObject e = new JSONObject(); e.put("type", "invite"); e.put("id", n); e.put("name", n); emit(e);
            } else if (op.equals("accept")) {
                if (c == conn) emit("connected", "name", connName);
            } else if (op.equals("decline")) {
                if (c == conn) { conn = null; emit("error", "message", connName + " declined."); }
                closeQuiet(c);
            } else if (op.equals("data")) {
                if (c == conn) emit("data", "data", o.optString("data"));
            }
        } catch (Exception ignored) {}
    }

    private synchronized void sendLine(Socket c, JSONObject o) throws Exception {
        OutputStream out = c.getOutputStream();
        out.write((o.toString() + "\n").getBytes(StandardCharsets.UTF_8));
        out.flush();
    }

    private static void closeQuiet(Socket s) { try { if (s != null) s.close(); } catch (Exception ignored) {} }
}

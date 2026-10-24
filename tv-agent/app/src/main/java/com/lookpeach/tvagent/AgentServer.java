package com.lookpeach.tvagent;

import android.util.Log;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** A tiny HTTP/1.1 server: one request per connection, bearer token, home network and Tailscale only. */
final class AgentServer {
    static final int PORT = 8765;
    private static final String TAG = "PeachAgent";
    private static final int MAX_HEADER = 8 * 1024;
    private static final int MAX_BODY = 4 * 1024;

    static final class Request {
        String method;
        String path;
        String query = "";
        final Map<String, String> headers = new HashMap<>();
        byte[] body = new byte[0];
        InetAddress remote;

        String bodyText() { return new String(body, StandardCharsets.UTF_8); }
    }

    static final class Response {
        final int code;
        final String type;
        final byte[] body;

        Response(int code, String type, byte[] body) { this.code = code; this.type = type; this.body = body; }

        static Response json(int code, String json) {
            return new Response(code, "application/json; charset=utf-8", json.getBytes(StandardCharsets.UTF_8));
        }

        static Response error(int code, String message) {
            return json(code, "{\"ok\":false,\"error\":" + Json.quote(message) + "}");
        }
    }

    interface Handler { Response handle(Request request); }
    interface TokenSource { String token(); }

    private final Handler handler;
    private final TokenSource tokens;
    private final ExecutorService workers = Executors.newFixedThreadPool(3);
    private volatile ServerSocket socket;
    private Thread acceptThread;

    AgentServer(Handler handler, TokenSource tokens) {
        this.handler = handler;
        this.tokens = tokens;
    }

    void start() {
        acceptThread = new Thread(this::acceptLoop, "peach-agent-http");
        acceptThread.setDaemon(true);
        acceptThread.start();
    }

    void stop() {
        ServerSocket s = socket;
        socket = null;
        if (s != null) try { s.close(); } catch (IOException ignored) { }
        workers.shutdownNow();
    }

    private void acceptLoop() {
        // The service can be re-bound right after a crash: retry the bind for a while instead of giving up.
        for (int attempt = 0; attempt < 30 && !workers.isShutdown(); attempt++) {
            try (ServerSocket s = new ServerSocket()) {
                s.setReuseAddress(true);
                s.bind(new InetSocketAddress(PORT));
                socket = s;
                Log.i(TAG, "listening on " + PORT);
                while (socket != null) {
                    Socket client = s.accept();
                    workers.execute(() -> serve(client));
                }
                return;
            } catch (IOException e) {
                if (socket == null && workers.isShutdown()) return;
                Log.w(TAG, "server socket: " + e.getMessage());
                try { Thread.sleep(2000); } catch (InterruptedException ie) { return; }
            }
        }
    }

    private void serve(Socket client) {
        try (Socket c = client) {
            c.setSoTimeout(10_000);
            InetAddress remote = c.getInetAddress();
            OutputStream out = c.getOutputStream();
            if (!allowed(remote)) {
                write(out, Response.error(403, "not from the home network or Tailscale"));
                return;
            }
            Request req = read(new BufferedInputStream(c.getInputStream()));
            if (req == null) {
                write(out, Response.error(400, "bad request"));
                return;
            }
            req.remote = remote;
            if (!authorised(req)) {
                write(out, Response.error(401, "wrong token"));
                return;
            }
            Response res;
            try {
                res = handler.handle(req);
            } catch (RuntimeException e) {
                Log.w(TAG, "handler", e);
                res = Response.error(500, String.valueOf(e.getMessage()));
            }
            write(out, res);
        } catch (IOException e) {
            Log.d(TAG, "client: " + e.getMessage());
        }
    }

    private boolean authorised(Request req) {
        String expected = tokens.token();
        String header = req.headers.get("authorization");
        if (expected == null || expected.isEmpty() || header == null) return false;
        String prefix = "bearer ";
        if (header.length() <= prefix.length() || !header.substring(0, prefix.length()).equalsIgnoreCase(prefix)) return false;
        byte[] given = header.substring(prefix.length()).trim().getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(given, expected.getBytes(StandardCharsets.UTF_8));
    }

    /** Loopback, private LAN ranges and Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48). */
    static boolean allowed(InetAddress a) {
        if (a == null) return false;
        if (a.isLoopbackAddress() || a.isSiteLocalAddress()) return true;
        byte[] b = a.getAddress();
        if (a instanceof Inet4Address) {
            return (b[0] & 0xff) == 100 && (b[1] & 0xc0) == 64;
        }
        if (a instanceof Inet6Address) {
            boolean mapped = true;
            for (int i = 0; i < 10; i++) if (b[i] != 0) { mapped = false; break; }
            if (mapped && (b[10] & 0xff) == 0xff && (b[11] & 0xff) == 0xff) {
                int b0 = b[12] & 0xff, b1 = b[13] & 0xff;
                return b0 == 127 || b0 == 10 || (b0 == 192 && b1 == 168) || (b0 == 172 && (b1 & 0xf0) == 16)
                        || (b0 == 100 && (b1 & 0xc0) == 64);
            }
            return (b[0] & 0xff) == 0xfd && (b[1] & 0xff) == 0x7a && (b[2] & 0xff) == 0x11
                    && (b[3] & 0xff) == 0x5c && (b[4] & 0xff) == 0xa1 && (b[5] & 0xff) == 0xe0;
        }
        return false;
    }

    private static Request read(InputStream in) throws IOException {
        ByteArrayOutputStream head = new ByteArrayOutputStream();
        int state = 0;
        while (state < 4) {
            int ch = in.read();
            if (ch < 0) return null;
            head.write(ch);
            if (head.size() > MAX_HEADER) return null;
            state = (ch == '\r' && (state == 0 || state == 2)) || (ch == '\n' && (state == 1 || state == 3)) ? state + 1 : 0;
        }
        String[] lines = head.toString("ISO-8859-1").split("\r\n");
        String[] first = lines[0].split(" ");
        if (first.length < 2) return null;
        Request r = new Request();
        r.method = first[0].toUpperCase(Locale.ROOT);
        String path = first[1];
        int q = path.indexOf('?');
        r.path = q >= 0 ? path.substring(0, q) : path;
        if (q >= 0) r.query = path.substring(q + 1);
        for (int i = 1; i < lines.length; i++) {
            int colon = lines[i].indexOf(':');
            if (colon > 0) {
                r.headers.put(lines[i].substring(0, colon).trim().toLowerCase(Locale.ROOT), lines[i].substring(colon + 1).trim());
            }
        }
        String len = r.headers.get("content-length");
        if (len != null) {
            int n;
            try { n = Integer.parseInt(len); } catch (NumberFormatException e) { return null; }
            if (n < 0 || n > MAX_BODY) return null;
            byte[] body = new byte[n];
            int off = 0;
            while (off < n) {
                int got = in.read(body, off, n - off);
                if (got < 0) return null;
                off += got;
            }
            r.body = body;
        }
        return r;
    }

    private static void write(OutputStream out, Response res) throws IOException {
        String reason = res.code == 200 ? "OK" : res.code == 401 ? "Unauthorized" : res.code == 403 ? "Forbidden"
                : res.code == 404 ? "Not Found" : res.code == 400 ? "Bad Request" : "Error";
        String head = "HTTP/1.1 " + res.code + " " + reason + "\r\n"
                + "Content-Type: " + res.type + "\r\n"
                + "Content-Length: " + res.body.length + "\r\n"
                + "Cache-Control: no-store\r\n"
                + "Connection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.ISO_8859_1));
        out.write(res.body);
        out.flush();
    }
}

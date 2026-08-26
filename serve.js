const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const HOST = "127.0.0.1";
const PORT = 8765;
const ROOT = path.join(__dirname);

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".wasm": "application/wasm",
};

const sockets = new Set();
let lastFrame = {
  cameraConnected: false,
  faceDetected: false,
  leftEye: "unknown",
  rightEye: "unknown",
  confidence: 0,
};

function framePacket(payload) {
  if (payload.length < 126) {
    const header = Buffer.alloc(2);
    header[0] = 0x81;
    header[1] = payload.length;
    return Buffer.concat([header, payload]);
  }
  const header = Buffer.alloc(4);
  header[0] = 0x81;
  header[1] = 126;
  header.writeUInt16BE(payload.length, 2);
  return Buffer.concat([header, payload]);
}

function send(socket, obj) {
  if (socket.readyState !== 1) return;
  socket.write(framePacket(Buffer.from(JSON.stringify(obj))));
}

function broadcast(obj) {
  const packet = framePacket(Buffer.from(JSON.stringify(obj)));
  for (const socket of sockets) {
    if (socket.readyState === 1) socket.write(packet);
  }
}

function acceptWs(req, socket) {
  const key = req.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return;
  }
  const accept = crypto
    .createHash("sha1")
    .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    .digest("base64");
  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\n" +
      "Connection: Upgrade\r\n" +
      "Sec-WebSocket-Accept: " +
      accept +
      "\r\n\r\n"
  );
  socket.readyState = 1;
  sockets.add(socket);
  send(socket, { type: "hello", lastFrame });
  socket.on("close", () => sockets.delete(socket));
  socket.on("error", () => sockets.delete(socket));
  socket.on("data", (buf) => {
    if (!buf.length) return;
    const opcode = buf[0] & 0x0f;
    if (opcode === 0x8) {
      sockets.delete(socket);
      socket.end();
      return;
    }
    if (opcode !== 0x1) return;
    const masked = (buf[1] & 0x80) !== 0;
    let len = buf[1] & 0x7f;
    let offset = 2;
    if (len === 126) {
      len = buf.readUInt16BE(2);
      offset = 4;
    }
    let payload;
    if (masked) {
      const mask = buf.slice(offset, offset + 4);
      offset += 4;
      payload = Buffer.alloc(len);
      for (let i = 0; i < len; i++) payload[i] = buf[offset + i] ^ mask[i % 4];
    } else {
      payload = buf.slice(offset, offset + len);
    }
    try {
      const msg = JSON.parse(payload.toString("utf8"));
      if (msg.type === "frame") {
        lastFrame = msg;
        broadcast(msg);
      } else if (msg.type === "blink") {
        broadcast(msg);
      }
    } catch (e) {}
  });
}

const server = http.createServer((req, res) => {
  if (req.headers.upgrade && req.headers.upgrade.toLowerCase() === "websocket") {
    return;
  }
  const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  const rel = urlPath === "/" ? "/demo/index.html" : urlPath;
  let filePath = path.join(ROOT, rel);
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("Not found: " + rel);
      return;
    }
    res.writeHead(200, { "Content-Type": TYPES[path.extname(filePath)] || "application/octet-stream" });
    res.end(data);
  });
});

server.on("upgrade", (req, socket) => acceptWs(req, socket));

server.listen(PORT, HOST, () => {
  console.log("Blink plugin demo: http://" + HOST + ":" + PORT + "/");
  console.log("Detector page:     http://" + HOST + ":" + PORT + "/detector/index.html");
  console.log("Godot should connect to ws://" + HOST + ":" + PORT);
});

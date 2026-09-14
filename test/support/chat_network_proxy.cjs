// LOCAL ONLY: fault-injection proxy for the opt-in FlutterFire browser test.
// Data 8788 -> Firestore emulator 8787; control 8789. No configurable remote host.
const http = require('node:http');
let offline = false;
const connections = new Set();
const data = http.createServer((req, res) => {
  if (offline) {
    res.writeHead(503, {'Access-Control-Allow-Origin': '*',
      'Content-Type': 'application/json'});
    res.end(JSON.stringify({error: {code: 503, status: 'UNAVAILABLE', message: 'Local test offline'}}));
    return;
  }
  const upstream = http.request({hostname: '127.0.0.1', port: 8787,
    path: req.url, method: req.method, headers: req.headers}, (reply) => {
    res.writeHead(reply.statusCode, reply.headers);
    reply.pipe(res);
  });
  upstream.on('error', () => {if (!res.headersSent) res.writeHead(503); res.end();});
  res.on('close', () => upstream.destroy());
  req.pipe(upstream);
});
data.on('connection', socket => {
  connections.add(socket);
  socket.on('close', () => connections.delete(socket));
});
const control = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') {res.writeHead(204); res.end(); return;}
  if (req.method !== 'POST' || !['/offline', '/online'].includes(req.url)) {
    res.writeHead(404); res.end(); return;
  }
  offline = req.url === '/offline';
  if (offline) for (const socket of connections) socket.destroy();
  res.writeHead(200); res.end(offline ? 'offline' : 'online');
});
data.listen(8788, '127.0.0.1');
control.listen(8789, '127.0.0.1', () => console.log('Local chat proxy ready (8788/8789)'));
function stop() {for (const socket of connections) socket.destroy(); data.close(); control.close();}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);

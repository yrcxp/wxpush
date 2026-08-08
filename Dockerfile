FROM node:20-slim
WORKDIR /app
COPY src/index.js /app/src/index.js
RUN mkdir -p /app/runtime
RUN cat <<'EOF' > /app/runtime/server.mjs
import http from 'node:http';
import { Readable } from 'node:stream';
import worker from '../src/index.js';

const port = process.env.PORT ? Number(process.env.PORT) : 3939;

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) {
    if (Array.isArray(v)) {
      for (const item of v) headers.append(k, item);
    } else if (v !== undefined) {
      headers.append(k, v);
    }
  }
  const method = req.method || 'GET';
  const body = method === 'GET' || method === 'HEAD' ? null : Readable.toWeb(req);
  const requestInit = { method, headers, body };
  if (body) requestInit.duplex = 'half';
  const request = new Request(url, requestInit);
  const env = { ...process.env };
  const ctx = { waitUntil: (p) => p?.catch(() => {}) };
  try {
    const response = await worker.fetch(request, env, ctx);
    res.statusCode = response.status;
    response.headers.forEach((value, key) => {
      res.setHeader(key, value);
    });
    if (response.body) {
      const reader = response.body.getReader();
      res.on('close', () => reader.cancel().catch(() => {}));
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(Buffer.from(value));
      }
    }
    res.end();
  } catch (err) {
    res.statusCode = 500;
    res.setHeader('content-type', 'text/plain; charset=utf-8');
    res.end(err?.message || 'Internal Server Error');
  }
});

server.listen(port);
EOF
EXPOSE 3939
CMD ["node", "/app/runtime/server.mjs"]
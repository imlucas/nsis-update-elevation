#!/usr/bin/env node
// single-range-test-server — deliberately mimics `npx http-server` (and most CDNs/S3 out
// of the box): honors a single `Range: bytes=a-b` request correctly (returns 206 with a
// Content-Range header, passing the naive "curl -r 0-99 -> 206" smoke test), but has no
// concept of a *combined* multi-range request. Use this to reproduce the documented
// failure mode before switching to differential-update-test-server.mjs to see the fix.
//
//   node server/single-range-test-server.mjs <dir> [port]
import { createServer } from 'node:http';
import { createReadStream, statSync } from 'node:fs';
import { join } from 'node:path';

const root = process.argv[2] ?? '.';
const port = Number(process.argv[3] ?? 8099);

createServer((req, res) => {
  const filePath = join(root, decodeURIComponent(req.url.split('?')[0]));
  let stat;
  try {
    stat = statSync(filePath);
  } catch {
    console.log(`${new Date().toISOString()} 404 ${req.method} ${req.url}`);
    res.writeHead(404);
    res.end();
    return;
  }

  const rangeHeader = req.headers['range'];
  if (!rangeHeader) {
    console.log(`${new Date().toISOString()} 200 ${req.method} ${req.url} bytesSent=${stat.size}`);
    res.writeHead(200, { 'Content-Length': stat.size, 'Accept-Ranges': 'bytes' });
    createReadStream(filePath).pipe(res);
    return;
  }

  // Only ever honors the FIRST range in the header, exactly like a plain static file
  // server that doesn't implement RFC 7233's multipart/byteranges. If electron-updater
  // sent a combined multi-range request, this silently answers as if only the first
  // range was requested -- which electron-updater's checkIsRangesSupported/DataSplitter
  // correctly reject as a malformed multi-range response, triggering the "Content-Type
  // multipart/byteranges is expected, but got ..." fallback-to-full-download error.
  const m = /bytes=(\d+)-(\d*)/.exec(rangeHeader);
  const start = parseInt(m[1], 10);
  const end = m[2] ? parseInt(m[2], 10) : stat.size - 1;
  const chunkSize = end - start + 1;
  console.log(`${new Date().toISOString()} 206 ${req.method} ${req.url} range=${rangeHeader} bytesSent=${chunkSize} (single-range only, no multipart support)`);
  res.writeHead(206, {
    'Content-Range': `bytes ${start}-${end}/${stat.size}`,
    'Content-Length': chunkSize,
    'Accept-Ranges': 'bytes',
  });
  createReadStream(filePath, { start, end }).pipe(res);
}).listen(port, () => console.log(`single-range-test-server listening on ${port}, serving ${root}`));

#!/usr/bin/env node
// differential-update-test-server — a static file server that actually supports the HTTP
// feature electron-updater's differential downloader requires: a single request naming
// MULTIPLE byte ranges (`Range: bytes=a-b, c-d, ...`), answered as one RFC 7233
// multipart/byteranges response (https://www.rfc-editor.org/rfc/rfc7233.html#section-4.1).
//
// Plain single-range servers (npx http-server, most CDNs/S3 out of the box) pass the
// naive "curl -r 0-99 -> 206" smoke test but still make electron-updater fall back to a
// full download every time, logging:
//   Cannot download differentially, fallback to full download: Error: Content-Type
//   "multipart/byteranges" is expected, but got "null"
// See electron-updater's differentialDownloader/multipleRangeDownloader.ts: whenever a
// download batch needs more than one remote range, it sends them combined in one Range
// header and requires a genuine multipart response — not a rerun of the single-range case.
// https://github.com/electron-userland/electron-builder/blob/master/packages/electron-updater/src/differentialDownloader/multipleRangeDownloader.ts
//
// This server's part framing is intentionally minimal: electron-updater's DataSplitter
// (differentialDownloader/DataSplitter.ts) discards each part's header block wholesale —
// it only ever scans forward for the next "\r\n\r\n" — so per-part Content-Type/
// Content-Range headers are cosmetic. What actually matters is the outer
// `Content-Type: multipart/byteranges; boundary=...` header and exact boundary framing
// bytes between parts.
//
//   node server/differential-update-test-server.mjs <dir> [port]
//     dir   directory to serve (e.g. an electron-builder dist\ folder)
//     port  default 8099
//
// Verified against electron-updater 6.6.x on a real Windows 11 machine — see README.md
// "Verdict 1" for the exact byte counts this produced.
import { createServer } from 'node:http';
import { closeSync, createReadStream, openSync, readSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = process.argv[2] ?? '.';
const port = Number(process.argv[3] ?? 8099);
const BOUNDARY = 'diffupd-verify-boundary';

function parseRanges(rangeHeader, size) {
  const spec = rangeHeader.replace(/^bytes=/, '');
  return spec.split(',').map(part => {
    const m = /^\s*(\d+)-(\d*)\s*$/.exec(part);
    const start = parseInt(m[1], 10);
    const end = m[2] ? parseInt(m[2], 10) : size - 1;
    return { start, end };
  });
}

createServer((req, res) => {
  const filePath = join(root, decodeURIComponent(req.url.split('?')[0]));
  const rangeHeader = req.headers['range'];

  let stat;
  try {
    stat = statSync(filePath);
  } catch {
    console.log(`${new Date().toISOString()} 404 ${req.method} ${req.url}`);
    res.writeHead(404);
    res.end();
    return;
  }

  if (!rangeHeader) {
    console.log(`${new Date().toISOString()} 200 ${req.method} ${req.url} bytesSent=${stat.size}`);
    res.writeHead(200, { 'Content-Length': stat.size, 'Accept-Ranges': 'bytes' });
    createReadStream(filePath).pipe(res);
    return;
  }

  const ranges = parseRanges(rangeHeader, stat.size);

  if (ranges.length === 1) {
    const { start, end } = ranges[0];
    const chunkSize = end - start + 1;
    console.log(`${new Date().toISOString()} 206 single-range ${req.method} ${req.url} range=${rangeHeader} bytesSent=${chunkSize}`);
    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${stat.size}`,
      'Content-Length': chunkSize,
      'Accept-Ranges': 'bytes',
    });
    createReadStream(filePath, { start, end }).pipe(res);
    return;
  }

  // Multi-range: exactly what a real differential download needs.
  const totalRequested = ranges.reduce((sum, r) => sum + (r.end - r.start + 1), 0);
  console.log(`${new Date().toISOString()} 206 multi-range(${ranges.length}) ${req.method} ${req.url} range=${rangeHeader} bytesSent=${totalRequested} (of ${stat.size} full)`);

  res.writeHead(206, {
    'Content-Type': `multipart/byteranges; boundary=${BOUNDARY}`,
    'Accept-Ranges': 'bytes',
  });

  const fd = openSync(filePath, 'r');
  let i = 0;
  const writeNext = () => {
    if (i >= ranges.length) {
      res.end(`\r\n--${BOUNDARY}--\r\n`);
      closeSync(fd);
      return;
    }
    const { start, end } = ranges[i++];
    const length = end - start + 1;
    const prefix = i === 1 ? `--${BOUNDARY}\r\n\r\n` : `\r\n--${BOUNDARY}\r\n\r\n`;
    res.write(prefix);
    const buf = Buffer.alloc(length);
    readSync(fd, buf, 0, length, start);
    if (res.write(buf)) {
      writeNext();
    } else {
      res.once('drain', writeNext);
    }
  };
  writeNext();
}).listen(port, () => console.log(`differential-update-test-server listening on ${port}, serving ${root}`));

// Generates AppIcon-1024.png — solid teal square with white "X5" wordmark.
// Run: node scripts/gen-icon.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

const __dirname = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(__dirname, '..', 'X5', 'Assets.xcassets', 'AppIcon.appiconset');
mkdirSync(outDir, { recursive: true });

const SIZE = 1024;
const ACCENT = [0, 217, 163];
const WHITE = [255, 255, 255];

function pngBuffer(width, height, drawPixel) {
  const channels = 3;
  const bytesPerRow = width * channels + 1;
  const raw = Buffer.alloc(bytesPerRow * height);
  for (let y = 0; y < height; y++) {
    raw[y * bytesPerRow] = 0;
    for (let x = 0; x < width; x++) {
      const px = drawPixel(x, y);
      const o = y * bytesPerRow + 1 + x * channels;
      raw[o] = px[0]; raw[o + 1] = px[1]; raw[o + 2] = px[2];
    }
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}
const CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }

// Glyph rendering for "X5" — bold geometric, centered
// Approach: build "X" stroke + "5" composed of segments. Render via SDF-like distance fields.

function rectFilled(x, y, x0, y0, x1, y1) {
  return x >= x0 && x <= x1 && y >= y0 && y <= y1;
}

// "X" — two diagonal strokes intersecting
function inXGlyph(x, y, cx, cy, half, thick) {
  if (Math.abs(x - cx) > half || Math.abs(y - cy) > half) return false;
  const dx = x - cx, dy = y - cy;
  const t = thick / Math.SQRT2; // perpendicular distance to a 45° line
  return Math.abs(dx - dy) <= t || Math.abs(dx + dy) <= t;
}

// "5" — top bar + left vertical + middle bar + bottom curve approx as right vertical + bottom bar
function inFiveGlyph(x, y, x0, y0, x1, y1, thick) {
  // bounding box
  if (x < x0 || x > x1 || y < y0 || y > y1) return false;
  const w = x1 - x0;
  const h = y1 - y0;
  const midY = y0 + h * 0.45;
  const t = thick;

  // Top horizontal bar
  if (rectFilled(x, y, x0, y0, x1, y0 + t)) return true;
  // Left vertical (only top half)
  if (rectFilled(x, y, x0, y0, x0 + t, midY)) return true;
  // Middle horizontal bar
  if (rectFilled(x, y, x0, midY - t / 2, x1 - t * 0.6, midY + t / 2)) return true;
  // Right vertical (bottom half) — emulating curve
  if (rectFilled(x, y, x1 - t, midY, x1, y1 - t)) return true;
  // Bottom horizontal bar
  if (rectFilled(x, y, x0, y1 - t, x1 - t * 0.2, y1)) return true;
  // Bottom-left corner of curve
  if (rectFilled(x, y, x0, y1 - t * 1.4, x0 + t * 1.2, y1)) return true;
  return false;
}

const cx = SIZE / 2, cy = SIZE / 2;
const glyphHeight = SIZE * 0.5;
const glyphThick = Math.round(SIZE * 0.085);
const halfX = glyphHeight / 2;
// Layout: X on the left, 5 on the right, with a small gap
const xCenterX = cx - SIZE * 0.13;
const fiveX0 = cx + SIZE * 0.02;
const fiveX1 = fiveX0 + glyphHeight * 0.78;
const fiveY0 = cy - halfX;
const fiveY1 = cy + halfX;

const buf = pngBuffer(SIZE, SIZE, (x, y) => {
  if (
    inXGlyph(x, y, xCenterX, cy, halfX, glyphThick) ||
    inFiveGlyph(x, y, fiveX0, fiveY0, fiveX1, fiveY1, glyphThick)
  ) {
    return WHITE;
  }
  return ACCENT;
});

writeFileSync(resolve(outDir, 'AppIcon-1024.png'), buf);
console.log('wrote AppIcon-1024.png (' + buf.length + ' bytes)');

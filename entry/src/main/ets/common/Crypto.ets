/**
 * CodexBar Mobile — 纯 TS 加密原语
 *
 * SHA-256 / HMAC-SHA256 / Base64URL 均为纯 TS 实现：ArkUI-X 三端零平台依赖，
 * 可本地单测。供火山引擎 V4 签名（common/VolcSign.ets，Doubao）与
 * AWS SigV4 签名（common/AwsSign.ets，Bedrock）共用。
 */

// ---------------- Base64URL ----------------

const B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** 字节数组 → Base64URL（无填充） */
export function base64UrlEncode(bytes: number[]): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : -1;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : -1;
    out += B64_ALPHABET.charAt(b0 >> 2);
    out += B64_ALPHABET.charAt(((b0 & 3) << 4) | (b1 >= 0 ? b1 >> 4 : 0));
    if (b1 < 0) {
      break;
    }
    out += B64_ALPHABET.charAt(((b1 & 15) << 2) | (b2 >= 0 ? b2 >> 6 : 0));
    if (b2 < 0) {
      break;
    }
    out += B64_ALPHABET.charAt(b2 & 63);
  }
  return out;
}

function b64UrlChar(c: string): number {
  const idx = B64_ALPHABET.indexOf(c);
  if (idx >= 0) {
    return idx;
  }
  if (c === '+') {
    return 62;
  }
  if (c === '/') {
    return 63;
  }
  return -1;
}

/** Base64URL（兼容标准 Base64）→ UTF-8 字符串 */
export function base64UrlDecode(text: string): string {
  const clean = text.replace(/=+$/, '');
  const bytes: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < clean.length; i++) {
    const v = b64UrlChar(clean.charAt(i));
    if (v < 0) {
      continue;
    }
    buffer = (buffer << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 0xff);
    }
  }
  // 字节流按 UTF-8 解码；非法序列回退 Latin-1
  let pct = '';
  for (let i = 0; i < bytes.length; i++) {
    pct += `%${bytes[i].toString(16).padStart(2, '0')}`;
  }
  try {
    return decodeURIComponent(pct);
  } catch (e) {
    let latin = '';
    for (let i = 0; i < bytes.length; i++) {
      latin += String.fromCharCode(bytes[i]);
    }
    return latin;
  }
}

// ---------------- SHA-256 / HMAC-SHA256 ----------------

/** 字符串 → UTF-8 字节数组 */
export function utf8Bytes(input: string): number[] {
  const bytes: number[] = [];
  const utf8 = encodeURIComponent(input);
  for (let i = 0; i < utf8.length; i++) {
    if (utf8.charAt(i) === '%') {
      bytes.push(parseInt(utf8.substring(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(utf8.charCodeAt(i));
    }
  }
  return bytes;
}

/** 字节数组 → 小写十六进制字符串 */
export function hexFromBytes(bytes: number[]): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

/** 纯 TS SHA-256（FIPS 180-4）：字节数组 → 32 字节 */
export function sha256Digest(input: number[]): number[] {
  const bytes: number[] = input.slice();
  const bitLen = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) {
    bytes.push(0);
  }
  const hi = Math.floor(bitLen / 0x100000000);
  const lo = bitLen >>> 0;
  bytes.push((hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff);
  bytes.push((lo >>> 24) & 0xff, (lo >>> 16) & 0xff, (lo >>> 8) & 0xff, lo & 0xff);

  const h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const w = new Array<number>(64);

  const rotr = (x: number, n: number): number => (x >>> n) | (x << (32 - n));

  for (let off = 0; off < bytes.length; off += 64) {
    for (let i = 0; i < 16; i++) {
      const j = off + i * 4;
      w[i] = ((bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let a = h[0];
    let b = h[1];
    let c = h[2];
    let d = h[3];
    let e = h[4];
    let f = h[5];
    let g = h[6];
    let hh = h[7];
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + S1 + ch + k[i] + w[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }
  const out: number[] = [];
  for (let i = 0; i < 8; i++) {
    out.push((h[i] >>> 24) & 0xff, (h[i] >>> 16) & 0xff, (h[i] >>> 8) & 0xff, h[i] & 0xff);
  }
  return out;
}

/** 纯 TS SHA-256：字符串 → 32 字节 */
export function sha256Bytes(input: string): number[] {
  return sha256Digest(utf8Bytes(input));
}

/** SHA-256 → Base64URL */
export function sha256Base64Url(input: string): string {
  return base64UrlEncode(sha256Bytes(input));
}

/** SHA-256 → 小写十六进制 */
export function sha256Hex(message: string): string {
  return hexFromBytes(sha256Digest(utf8Bytes(message)));
}

/** SHA-256（字节输入）→ 小写十六进制 */
export function sha256HexOfBytes(bytes: number[]): string {
  return hexFromBytes(sha256Digest(bytes));
}

/** HMAC 分组长度（SHA-256） */
const BLOCK_SIZE = 64;

/** HMAC-SHA256：key / message 均为字节数组，返回 32 字节摘要 */
export function hmacSha256(key: number[], message: number[]): number[] {
  let k = key.slice();
  if (k.length > BLOCK_SIZE) {
    k = sha256Digest(k);
  }
  const pad = new Array<number>(BLOCK_SIZE);
  for (let i = 0; i < BLOCK_SIZE; i++) {
    pad[i] = i < k.length ? k[i] : 0;
  }
  const inner = new Array<number>(BLOCK_SIZE + message.length);
  for (let i = 0; i < BLOCK_SIZE; i++) {
    inner[i] = pad[i] ^ 0x36;
  }
  for (let i = 0; i < message.length; i++) {
    inner[BLOCK_SIZE + i] = message[i];
  }
  const innerHash = sha256Digest(inner);
  const outer = new Array<number>(BLOCK_SIZE + innerHash.length);
  for (let i = 0; i < BLOCK_SIZE; i++) {
    outer[i] = pad[i] ^ 0x5c;
  }
  for (let i = 0; i < innerHash.length; i++) {
    outer[BLOCK_SIZE + i] = innerHash[i];
  }
  return sha256Digest(outer);
}

/** HMAC-SHA256 → 小写十六进制 */
export function hmacSha256Hex(key: number[], message: string): string {
  return hexFromBytes(hmacSha256(key, utf8Bytes(message)));
}

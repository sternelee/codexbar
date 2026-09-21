/**
 * CodexBar Mobile — 火山引擎 V4 请求签名（HMAC-SHA256）
 *
 * 对照 macOS 版 Providers/Doubao/DoubaoVolcengineSigner.swift 迁移：火山引擎
 * Top OpenAPI（open.volcengineapi.com）与 AWS SigV4 同构——规范化请求 →
 * 派生签名密钥（date/region/service/request 四级 HMAC）→ 计算签名。
 *
 * 纯 TS 实现：ArkUI-X 三端零平台依赖，可本地单测（SHA-256 复用 common/OAuth）。
 */

import { hexFromBytes, sha256Digest, utf8Bytes } from './OAuth';

/** HMAC 分组长度（SHA-256） */
const BLOCK_SIZE = 64;
const ALGORITHM = 'HMAC-SHA256';
const SERVICE = 'ark';
const TERMINATOR = 'request';
/** 规范化/签名头须按小写名字典序排列（服务端会重排校验，乱序 → HTTP 403） */
const SIGNED_HEADERS = 'content-type;host;x-content-sha256;x-date';

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

/** SHA-256 → 小写十六进制 */
export function sha256Hex(message: string): string {
  return hexFromBytes(sha256Digest(utf8Bytes(message)));
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** Unix 毫秒 → yyyyMMdd'T'HHmmss'Z'（UTC） */
export function volcTimestamp(ms: number): string {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}` +
    `T${pad2(d.getUTCHours())}${pad2(d.getUTCMinutes())}${pad2(d.getUTCSeconds())}Z`;
}

/** Unix 毫秒 → yyyyMMdd（UTC） */
export function volcDateStamp(ms: number): string {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}`;
}

/** AWS 风格 percent-encode（保留 -_.~；encodeSlash=false 时额外保留 /） */
export function volcPercentEncode(value: string, encodeSlash: boolean): string {
  let out = '';
  const bytes = utf8Bytes(value);
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    const ch = String.fromCharCode(b);
    const unreserved = (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) ||
      (b >= 0x30 && b <= 0x39) || ch === '-' || ch === '_' || ch === '.' || ch === '~';
    if (unreserved || (!encodeSlash && ch === '/')) {
      out += ch;
    } else {
      out += `%${b.toString(16).toUpperCase().padStart(2, '0')}`;
    }
  }
  return out;
}

/** 从 URL 取主机名（含端口；无协议时按整串处理） */
export function volcHostOf(url: string): string {
  const scheme = url.indexOf('://');
  const rest = scheme >= 0 ? url.substring(scheme + 3) : url;
  let hostPort = rest;
  const slash = rest.indexOf('/');
  if (slash >= 0) {
    hostPort = rest.substring(0, slash);
  }
  const q = hostPort.indexOf('?');
  if (q >= 0) {
    hostPort = hostPort.substring(0, q);
  }
  return hostPort;
}

/** 从 URL 取规范化查询串（名与值 percent-encode 后按 key/value 字典序排序） */
export function volcCanonicalQuery(url: string): string {
  const qIdx = url.indexOf('?');
  if (qIdx < 0) {
    return '';
  }
  let query = url.substring(qIdx + 1);
  const hash = query.indexOf('#');
  if (hash >= 0) {
    query = query.substring(0, hash);
  }
  if (query.length === 0) {
    return '';
  }
  const keys: string[] = [];
  const values: string[] = [];
  const parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0) {
      continue;
    }
    const eq = parts[i].indexOf('=');
    const rawK = eq >= 0 ? parts[i].substring(0, eq) : parts[i];
    const rawV = eq >= 0 ? parts[i].substring(eq + 1) : '';
    keys.push(volcPercentEncode(decodeURIComponent(rawK), true));
    values.push(volcPercentEncode(decodeURIComponent(rawV), true));
  }
  // 插入排序：按 (key, value) 字典序
  for (let i = 1; i < keys.length; i++) {
    for (let j = i; j > 0; j--) {
      const prevKey = keys[j - 1];
      const curKey = keys[j];
      const swap = prevKey > curKey || (prevKey === curKey && values[j - 1] > values[j]);
      if (!swap) {
        break;
      }
      keys[j - 1] = curKey;
      keys[j] = prevKey;
      const prevVal = values[j - 1];
      values[j - 1] = values[j];
      values[j] = prevVal;
    }
  }
  const pairs: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    pairs.push(`${keys[i]}=${values[i]}`);
  }
  return pairs.join('&');
}

/** 从 URL 取规范化 URI（默认 /，保留斜杠） */
export function volcCanonicalUri(url: string): string {
  const scheme = url.indexOf('://');
  const rest = scheme >= 0 ? url.substring(scheme + 3) : url;
  let path = '/';
  const slash = rest.indexOf('/');
  if (slash >= 0) {
    path = rest.substring(slash);
  }
  const q = path.indexOf('?');
  if (q >= 0) {
    path = path.substring(0, q);
  }
  const hash = path.indexOf('#');
  if (hash >= 0) {
    path = path.substring(0, hash);
  }
  if (path.length === 0) {
    return '/';
  }
  return volcPercentEncode(decodeURIComponent(path), false);
}

export interface VolcCredentials {
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
}

export class VolcSignResult {
  /** 需随请求发送的头（Authorization / X-Date / X-Content-Sha256 / Content-Type） */
  headers: Record<string, string> = {};
  canonicalRequest: string = '';
  stringToSign: string = '';
  signature: string = '';
}

/**
 * 生成签名结果。body 参与 payload 哈希（空串表示空请求体）。
 * 注意：Host 头由 HTTP 客户端自动携带，不在此显式设置，但仍计入规范化请求。
 */
export function signVolcRequest(
  method: string,
  url: string,
  contentType: string,
  body: string,
  credentials: VolcCredentials,
  timestampMs: number
): VolcSignResult {
  const timestamp = volcTimestamp(timestampMs);
  const dateStamp = volcDateStamp(timestampMs);
  const payloadHash = sha256Hex(body);
  const host = volcHostOf(url);
  const canonicalRequest = [
    method,
    volcCanonicalUri(url),
    volcCanonicalQuery(url),
    `content-type:${contentType}`,
    `host:${host}`,
    `x-content-sha256:${payloadHash}`,
    `x-date:${timestamp}`,
    '',
    SIGNED_HEADERS,
    payloadHash,
  ].join('\n');
  const credentialScope = `${dateStamp}/${credentials.region}/${SERVICE}/${TERMINATOR}`;
  const stringToSign = [
    ALGORITHM,
    timestamp,
    credentialScope,
    sha256Hex(canonicalRequest),
  ].join('\n');

  const dateKey = hmacSha256(utf8Bytes(credentials.secretAccessKey), utf8Bytes(dateStamp));
  const regionKey = hmacSha256(dateKey, utf8Bytes(credentials.region));
  const serviceKey = hmacSha256(regionKey, utf8Bytes(SERVICE));
  const signingKey = hmacSha256(serviceKey, utf8Bytes(TERMINATOR));
  const signature = hmacSha256Hex(signingKey, stringToSign);

  const result = new VolcSignResult();
  result.canonicalRequest = canonicalRequest;
  result.stringToSign = stringToSign;
  result.signature = signature;
  const headers: Record<string, string> = {};
  headers['content-type'] = contentType;
  headers['x-date'] = timestamp;
  headers['x-content-sha256'] = payloadHash;
  headers['authorization'] =
    `${ALGORITHM} Credential=${credentials.accessKeyId}/${credentialScope}, ` +
    `SignedHeaders=${SIGNED_HEADERS}, Signature=${signature}`;
  result.headers = headers;
  return result;
}

/**
 * CodexBar Mobile — OAuth / 网页登录辅助
 *
 * Codex (ChatGPT)：完整 PKCE 授权码流程，参数与 Codex CLI 一致
 *   （client_id app_EMoamEEZ73f0CkXaXp7hrann，回调 localhost:1455，
 *     由应用内 Web 组件拦截回调地址后换取令牌）。
 * Claude：应用内 Web 组件登录 claude.ai 后读取 sessionKey Cookie。
 *
 * SHA-256 / Base64URL 为纯 TS 实现：ArkUI-X 三端零平台依赖，可本地单测。
 */

import { Http } from '../net/Http';
import { asObj, Json, parseJson, str } from '../net/Json';

// ---------------- Base64URL / SHA-256（纯 TS） ----------------

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

/** 纯 TS SHA-256（FIPS 180-4）：字符串 → 32 字节 */
export function sha256Bytes(input: string): number[] {
  return sha256Digest(utf8Bytes(input));
}

/** SHA-256 → Base64URL（PKCE S256 challenge 即此值） */
export function sha256Base64Url(input: string): string {
  return base64UrlEncode(sha256Bytes(input));
}

// ---------------- PKCE / Codex OAuth ----------------

const CODEX_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const CODEX_AUTHORIZE = 'https://auth.openai.com/oauth/authorize';
const CODEX_TOKEN = 'https://auth.openai.com/oauth/token';
const CODEX_REDIRECT = 'http://localhost:1455/auth/callback';
const CODEX_SCOPE = 'openid profile email offline_access api.connectors.read api.connectors.invoke';

export interface PkcePair {
  verifier: string;
  challenge: string;
  state: string;
}

const VERIFIER_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/** 生成 PKCE 三元组（verifier 64 字符；随机源为 Math.random+时间混合，客户端侧够用） */
export function makePkce(now: number): PkcePair {
  let seed = `${now}_${Math.random()}_${Math.random()}`;
  let verifier = '';
  while (verifier.length < 64) {
    seed = sha256Base64Url(seed + `_${Math.random()}`);
    for (let i = 0; i < seed.length && verifier.length < 96; i++) {
      verifier += VERIFIER_CHARS.charAt(seed.charCodeAt(i) % VERIFIER_CHARS.length);
    }
  }
  return {
    verifier: verifier,
    challenge: sha256Base64Url(verifier),
    state: sha256Base64Url(`${verifier}_state_${now}`).substring(0, 24),
  };
}

/** 构造授权页地址 */
export function codexAuthorizeUrl(pkce: PkcePair): string {
  const q = [
    `response_type=code`,
    `client_id=${encodeURIComponent(CODEX_CLIENT_ID)}`,
    `redirect_uri=${encodeURIComponent(CODEX_REDIRECT)}`,
    `scope=${encodeURIComponent(CODEX_SCOPE)}`,
    `state=${encodeURIComponent(pkce.state)}`,
    `code_challenge=${encodeURIComponent(pkce.challenge)}`,
    `code_challenge_method=S256`,
  ].join('&');
  return `${CODEX_AUTHORIZE}?${q}`;
}

export interface CallbackCode {
  code: string;
  state: string;
}

/** 解析回调地址中的 code/state（也容忍仅查询串输入） */
export function parseCallbackUrl(url: string): CallbackCode | null {
  if (url == null || url.length === 0) {
    return null;
  }
  const qIdx = url.indexOf('?');
  if (qIdx < 0) {
    return null;
  }
  const query = url.substring(qIdx + 1).split('#')[0];
  let code = '';
  let state = '';
  const parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    const kv = parts[i].split('=');
    if (kv.length >= 2 && kv[0] === 'code') {
      code = decodeURIComponent(kv[1]);
    }
    if (kv.length >= 2 && kv[0] === 'state') {
      state = decodeURIComponent(kv[1]);
    }
  }
  if (code.length === 0) {
    return null;
  }
  return { code: code, state: state };
}

/** 解析 JWT payload（不验签，仅取声明） */
export function decodeJwtPayload(jwt: string): Record<string, Json> | null {
  const segs = jwt.split('.');
  if (segs.length < 2) {
    return null;
  }
  const json = parseJson(base64UrlDecode(segs[1]));
  return asObj(json);
}

/** 从 Codex access token（JWT）提取 ChatGPT 账号 ID；根声明与 auth 嵌套声明都找 */
export function extractChatgptAccountId(accessToken: string): string {
  const payload = decodeJwtPayload(accessToken);
  if (payload == null) {
    return '';
  }
  const direct = payload['chatgpt_account_id'];
  if (typeof direct === 'string' && (direct as string).length > 0) {
    return direct as string;
  }
  const auth = asObj(payload['https://api.openai.com/auth']);
  if (auth != null) {
    const nested = auth['chatgpt_account_id'];
    if (typeof nested === 'string' && (nested as string).length > 0) {
      return nested as string;
    }
  }
  return '';
}

export interface CodexTokenSet {
  accessToken: string;
  refreshToken: string;
  accountId: string;
  error: string;
}

function formEncode(fields: string[][]): string {
  return fields
    .map((kv: string[]) => `${encodeURIComponent(kv[0])}=${encodeURIComponent(kv[1])}`)
    .join('&');
}

/** 授权码换令牌 */
export async function codexExchangeCode(code: string, verifier: string): Promise<CodexTokenSet> {
  const body = formEncode([
    ['grant_type', 'authorization_code'],
    ['code', code],
    ['code_verifier', verifier],
    ['client_id', CODEX_CLIENT_ID],
    ['redirect_uri', CODEX_REDIRECT],
  ]);
  return codexTokenRequest(body);
}

/** 刷新令牌 */
export async function codexRefreshToken(refreshToken: string): Promise<CodexTokenSet> {
  const body = formEncode([
    ['grant_type', 'refresh_token'],
    ['refresh_token', refreshToken],
    ['client_id', CODEX_CLIENT_ID],
  ]);
  return codexTokenRequest(body);
}

async function codexTokenRequest(formBody: string): Promise<CodexTokenSet> {
  const resp = await Http.post(
    CODEX_TOKEN,
    { 'content-type': 'application/x-www-form-urlencoded', 'accept': 'application/json' },
    formBody
  );
  const root = asObj(resp.json());
  if (!resp.ok || root == null) {
    const err = root != null ? str(root, 'error', '') : '';
    const msg = err.length > 0 ? err : `HTTP ${resp.code}`;
    const fail: CodexTokenSet = { accessToken: '', refreshToken: '', accountId: '', error: `令牌交换失败（${msg}）` };
    return fail;
  }
  const token = str(root, 'access_token', '');
  if (token.length === 0) {
    const fail: CodexTokenSet = { accessToken: '', refreshToken: '', accountId: '', error: '响应缺少 access_token' };
    return fail;
  }
  const set: CodexTokenSet = {
    accessToken: token,
    refreshToken: str(root, 'refresh_token', ''),
    accountId: extractChatgptAccountId(token),
    error: '',
  };
  return set;
}

// ---------------- Claude sessionKey ----------------

/** 从 Cookie 串中提取 sessionKey 值（形如 sk-ant-sid01-…） */
/** 平台会话令牌的可用性（对照 DeepSeekPlatformTokenImporter.isPlausibleToken：≥20 字符且不含空白） */
function plausiblePlatformToken(value: string): boolean {
  const trimmed = value.trim();
  if (trimmed.length < 20) {
    return false;
  }
  return !/\s/.test(trimmed);
}

/**
 * platform.deepseek.com 的 localStorage `userToken` → 平台会话令牌。
 *
 * 对照 macOS 的 `DeepSeekPlatformTokenImporter.extractUserToken` / `token(fromJSONObject)`：
 * 该键可能是裸字符串、带引号的字符串、或 `{ value | token | access_token | accessToken | userToken }`
 * 对象（甚至是被 JSON 序列化过的一层），四种形态都要能取出。
 */
export function extractDeepSeekUserToken(rawValue: string): string {
  const trimmed = rawValue == null ? '' : rawValue.trim();
  if (trimmed.length === 0) {
    return '';
  }
  // 1) JSON 形态：字符串 / 对象
  if (trimmed.charAt(0) === '"' || trimmed.charAt(0) === '{') {
    try {
      const parsed = JSON.parse(trimmed) as Object;
      if (typeof parsed === 'string') {
        const text = parsed as string;
        return plausiblePlatformToken(text) ? text.trim() : '';
      }
      if (parsed != null && typeof parsed === 'object') {
        const bag = parsed as Record<string, Object>;
        const keys: string[] = ['value', 'token', 'access_token', 'accessToken', 'userToken'];
        for (let i = 0; i < keys.length; i++) {
          const candidate = bag[keys[i]];
          if (typeof candidate === 'string' && plausiblePlatformToken(candidate as string)) {
            return (candidate as string).trim();
          }
        }
      }
      return '';
    } catch (e) {
      // 不是 JSON，按裸字符串继续
    }
  }
  // 2) 裸字符串 / 单双引号包裹
  const first = trimmed.charAt(0);
  const last = trimmed.charAt(trimmed.length - 1);
  const unquoted = trimmed.length >= 2 && ((first === '"' && last === '"') || (first === '\'' && last === '\''))
    ? trimmed.substring(1, trimmed.length - 1)
    : trimmed;
  return plausiblePlatformToken(unquoted) ? unquoted : '';
}

export function extractSessionKey(cookieText: string): string {
  if (cookieText == null || cookieText.length === 0) {
    return '';
  }
  const parts = cookieText.split(';');
  for (let i = 0; i < parts.length; i++) {
    const kv = parts[i].trim();
    if (kv.startsWith('sessionKey=')) {
      return kv.substring('sessionKey='.length).trim();
    }
  }
  return '';
}

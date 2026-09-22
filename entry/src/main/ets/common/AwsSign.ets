/**
 * CodexBar Mobile — AWS SigV4 请求签名
 *
 * 对照 macOS 版 Sources/CodexBarCore/Providers/Bedrock/BedrockAWSSigner.swift 迁移，
 * 供 Bedrock 使用（AWS Cost Explorer + CloudWatch）。与 common/VolcSign.ets 同构
 * （火山引擎 V4 即 AWS SigV4 的变体），复用 Crypto 的 SHA-256 / HMAC-SHA256 与规范化
 * 工具，纯 TS 三端零依赖、可本地单测。
 *
 * 与源工程一致：payload 哈希额外放进 x-amz-content-sha256 并计入签名头
 * （BedrockAWSSigner 同样无条件添加该头）；未携带该头的调用方可关闭以对齐。
 *
 * 注意：Host 头由 HTTP 客户端按 URL 自动生成，这里只参与规范化与签名，不作为
 * 请求头下发（与 VolcSign 的处理一致）。
 */

import { hmacSha256, hmacSha256Hex, sha256Hex, utf8Bytes } from './Crypto';
import {
  volcCanonicalQuery,
  volcCanonicalUri,
  volcDateStamp,
  volcHostOf,
  volcTimestamp
} from './VolcSign';

const ALGORITHM = 'AWS4-HMAC-SHA256';
const TERMINATOR = 'aws4_request';

export interface AwsCredentials {
  accessKeyId: string;
  secretAccessKey: string;
  /** 临时凭证的会话令牌；空串表示长期凭证 */
  sessionToken: string;
}

export class AwsSignResult {
  /** 需随请求发送的头（Authorization + 参与签名的头，不含 Host） */
  headers: Record<string, string> = {};
  canonicalRequest: string = '';
  stringToSign: string = '';
  signedHeaders: string = '';
  signature: string = '';
}

/** 头值规范化：去首尾空白 + 连续空白折叠为单空格（SigV4 规范要求） */
export function awsHeaderValue(value: string): string {
  return value.trim().replace(/\s+/g, ' ');
}

/**
 * 派生签名密钥：HMAC-SHA256 四级链
 * （AWS4+secret → date → region → service → aws4_request）。
 */
export function awsSigningKey(
  secretAccessKey: string,
  dateStamp: string,
  region: string,
  service: string
): number[] {
  const dateKey = hmacSha256(utf8Bytes(`AWS4${secretAccessKey}`), utf8Bytes(dateStamp));
  const regionKey = hmacSha256(dateKey, utf8Bytes(region));
  const serviceKey = hmacSha256(regionKey, utf8Bytes(service));
  return hmacSha256(serviceKey, utf8Bytes(TERMINATOR));
}

/**
 * 为一个请求生成 SigV4 签名头。
 *
 * @param method HTTP 方法
 * @param url 完整 URL（host 与查询串从中提取）
 * @param service 服务码，如 ce / monitoring
 * @param region 签名区域
 * @param headers 业务头（会被小写化并全部计入签名）
 * @param body 请求体（空串表示空体）
 * @param credentials 静态凭证
 * @param timestampMs 签名时间（Unix 毫秒，UTC 格式化）
 * @param withPayloadHash 是否添加并签名 x-amz-content-sha256
 */
export function signAwsRequest(
  method: string,
  url: string,
  service: string,
  region: string,
  headers: Record<string, string>,
  body: string,
  credentials: AwsCredentials,
  timestampMs: number,
  withPayloadHash: boolean
): AwsSignResult {
  const amzDate = volcTimestamp(timestampMs);
  const dateStamp = volcDateStamp(timestampMs);
  const payloadHash = sha256Hex(body);

  const map: Record<string, string> = {};
  const inputNames = Object.keys(headers);
  for (let i = 0; i < inputNames.length; i++) {
    map[inputNames[i].toLowerCase()] = awsHeaderValue(headers[inputNames[i]]);
  }
  const host = volcHostOf(url);
  if (host.length > 0) {
    map['host'] = host;
  }
  map['x-amz-date'] = amzDate;
  if (withPayloadHash) {
    map['x-amz-content-sha256'] = payloadHash;
  }
  const sessionToken = credentials.sessionToken.trim();
  if (sessionToken.length > 0) {
    map['x-amz-security-token'] = sessionToken;
  }

  const names: string[] = Object.keys(map);
  names.sort((a: string, b: string): number => (a < b ? -1 : (a > b ? 1 : 0)));
  let canonicalHeaders = '';
  for (let i = 0; i < names.length; i++) {
    canonicalHeaders += `${names[i]}:${map[names[i]]}\n`;
  }
  const signedHeaders = names.join(';');

  const canonicalRequest = [
    method.toUpperCase(),
    volcCanonicalUri(url),
    volcCanonicalQuery(url),
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const credentialScope = `${dateStamp}/${region}/${service}/${TERMINATOR}`;
  const stringToSign = [
    ALGORITHM,
    amzDate,
    credentialScope,
    sha256Hex(canonicalRequest),
  ].join('\n');

  const signature = hmacSha256Hex(
    awsSigningKey(credentials.secretAccessKey, dateStamp, region, service),
    stringToSign
  );

  const result = new AwsSignResult();
  result.canonicalRequest = canonicalRequest;
  result.stringToSign = stringToSign;
  result.signedHeaders = signedHeaders;
  result.signature = signature;
  const out: Record<string, string> = {};
  for (let i = 0; i < names.length; i++) {
    if (names[i] !== 'host') {
      out[names[i]] = map[names[i]];
    }
  }
  out['authorization'] =
    `${ALGORITHM} Credential=${credentials.accessKeyId}/${credentialScope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;
  result.headers = out;
  return result;
}

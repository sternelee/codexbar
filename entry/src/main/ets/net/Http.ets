/**
 * CodexBar Mobile — HTTP 客户端
 * 封装 @ohos.net.http；ArkUI-X 在 Android/iOS 上映射同组 API。
 */

import http from '@ohos.net.http';
import { parseJson, Json } from './Json';
import { L } from '../common/I18n';

export class HttpResult {
  code: number = 0;
  body: string = '';
  /** 响应头（键统一小写），供读取 x-ratelimit-* 等头部使用 */
  headers: Record<string, string> = {};

  get ok(): boolean {
    return this.code >= 200 && this.code < 300;
  }

  json(): Json {
    return parseJson(this.body);
  }

  errorText(): string {
    if (this.code === 401 || this.code === 403) {
      return L('凭证无效或已过期', 'Invalid credential or expired');
    }
    if (this.code === 429) {
      return L('请求过于频繁，请稍后再试', 'Rate limited. Please retry later');
    }
    if (this.code >= 500) {
      return L(`服务商服务端错误 (${this.code})`, `Provider server error (${this.code})`);
    }
    if (this.code === 0) {
      return L('网络请求失败，请检查网络', 'Network request failed. Check your connection');
    }
    return L(`请求失败 (HTTP ${this.code})`, `Request failed (HTTP ${this.code})`);
  }
}

export class Http {
  private static readonly TIMEOUT_MS: number = 20000;

  static async request(
    method: string,
    url: string,
    headers: Record<string, string>,
    extraData?: string
  ): Promise<HttpResult> {
    const result = new HttpResult();
    const client = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST :
          method === 'PUT' ? http.RequestMethod.PUT :
            method === 'DELETE' ? http.RequestMethod.DELETE : http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: Http.TIMEOUT_MS,
        readTimeout: Http.TIMEOUT_MS,
      };
      if (extraData != null && extraData.length > 0) {
        opts.extraData = extraData;
      }
      const resp = await client.request(url, opts);
      result.code = resp.responseCode;
      const raw = resp.result;
      result.body = typeof raw === 'string' ? raw : JSON.stringify(raw);
      const hdr = resp.header;
      if (hdr != null) {
        const rec = hdr as Record<string, Object>;
        const hkeys = Object.keys(rec);
        for (let i = 0; i < hkeys.length; i++) {
          const hv = rec[hkeys[i]];
          result.headers[hkeys[i].toLowerCase()] = typeof hv === 'string' ? hv as string : `${hv}`;
        }
      }
    } catch (e) {
      result.code = 0;
      result.body = e instanceof Error ? e.message : `${e}`;
    } finally {
      client.destroy();
    }
    return result;
  }

  static get(url: string, headers: Record<string, string>): Promise<HttpResult> {
    return Http.request('GET', url, headers);
  }

  static post(url: string, headers: Record<string, string>, body: string): Promise<HttpResult> {
    return Http.request('POST', url, headers, body);
  }
}

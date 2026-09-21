/**
 * CodexBar Mobile — HTTP 客户端
 * 封装 @ohos.net.http；ArkUI-X 在 Android/iOS 上映射同组 API。
 */

import http from '@ohos.net.http';
import { parseJson, Json } from './Json';

export class HttpResult {
  code: number = 0;
  body: string = '';

  get ok(): boolean {
    return this.code >= 200 && this.code < 300;
  }

  json(): Json {
    return parseJson(this.body);
  }

  errorText(): string {
    if (this.code === 401 || this.code === 403) {
      return '凭证无效或已过期';
    }
    if (this.code === 429) {
      return '请求过于频繁，请稍后再试';
    }
    if (this.code >= 500) {
      return `服务商服务端错误 (${this.code})`;
    }
    if (this.code === 0) {
      return '网络请求失败，请检查网络';
    }
    return `请求失败 (HTTP ${this.code})`;
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

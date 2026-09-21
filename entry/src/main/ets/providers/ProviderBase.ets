/**
 * CodexBar Mobile — Provider 接口与注册表
 * 对应 macOS 版 UsageFetcher 协议体系；每个服务商一个实现类。
 */

import {
  AuthKind,
  ProviderDescriptor,
  ProviderSetting,
  UsageSnapshot
} from '../model/Models';

/** 单个服务商的用量查询实现 */
export interface UsageProvider {
  descriptor: ProviderDescriptor;
  /** 拉取用量快照；失败时返回 ok=false 的快照而不是抛异常 */
  fetch(setting: ProviderSetting): Promise<UsageSnapshot>;
}

/** 服务商 URL 编码工具 */
export class UrlUtil {
  static encode(s: string): string {
    return encodeURIComponent(s);
  }
}

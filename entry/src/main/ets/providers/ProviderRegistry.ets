/**
 * Provider 注册表
 * 新增服务商在此登记即可（对照 macOS 版 ProviderDescriptor 目录）。
 */

import { ProviderDescriptor } from '../model/Models';
import { UsageProvider } from './ProviderBase';
import { createClaudeProvider } from './ClaudeProvider';
import { createCodexProvider } from './CodexProvider';
import {
  createAnthropicConsoleProvider,
  createDeepSeekProvider,
  createMoonshotProvider,
  createOpenAIPlatformProvider,
  createOpenRouterProvider,
  createSiliconFlowProvider
} from './ApiKeyProviders';
import { createDemoProvider } from './DemoProvider';
import {
  createChutesProvider,
  createDeepInfraProvider,
  createKimiCodingProvider,
  createManusProvider,
  createPerplexityProvider,
  createZenMuxProvider
} from './MoreProviders';
import {
  createKiloProvider,
  createMiMoProvider,
  createMiniMaxProvider,
  createMistralProvider,
  createPoeProvider,
  createT3ChatProvider,
  createZaiProvider
} from './MoreProviders2';
import {
  createClawRouterProvider,
  createClinePassProvider,
  createCrofProvider,
  createDeepgramProvider,
  createMuseProvider,
  createNousProvider,
  createQoderProvider,
  createSyntheticProvider,
  createVeniceProvider,
  createXaiProvider,
  createLiteLLMProvider,
  createLLMProxyProvider
} from './MoreProviders3';
import {
  createAbacusProvider,
  createAiAndProvider,
  createCodebuffProvider,
  createCommandCodeProvider,
  createDevinProvider,
  createElevenLabsProvider,
  createFireworksProvider,
  createIBMBobProvider,
  createLongCatProvider,
  createNeuralWattProvider,
  createNotionProvider,
  createSub2ApiProvider,
  createZoomMateProvider
} from './MoreProviders4';
import { createAlibabaCodingPlanProvider, createFactoryProvider } from './MoreProviders6';
import {
  createAmpProvider,
  createAzureOpenAIProvider,
  createCopilotProvider,
  createOllamaProvider,
  createV0Provider
} from './ApiKeyProviders2';
import { createDoubaoProvider } from './DoubaoProvider';
import { createBedrockProvider } from './BedrockProvider';
import {
  createGroqProvider,
  createHuggingFaceProvider,
  createOpenCodeGoProvider,
  createOpenCodeProvider,
  createWarpProvider
} from './MoreProviders5';

export class ProviderRegistry {
  private static providers: UsageProvider[] = [];

  /** 全部已登记服务商（按展示顺序） */
  static all(): UsageProvider[] {
    if (ProviderRegistry.providers.length === 0) {
      ProviderRegistry.providers = [
        createClaudeProvider(),
        createCodexProvider(),
        createOpenAIPlatformProvider(),
        createAnthropicConsoleProvider(),
        createOpenRouterProvider(),
        createDeepSeekProvider(),
        createMoonshotProvider(),
        createSiliconFlowProvider(),
        createKimiCodingProvider(),
        createZenMuxProvider(),
        createManusProvider(),
        createDeepInfraProvider(),
        createPerplexityProvider(),
        createChutesProvider(),
        createMiniMaxProvider(),
        createMiMoProvider(),
        createMistralProvider(),
        createKiloProvider(),
        createPoeProvider(),
        createT3ChatProvider(),
        createZaiProvider(),
        createXaiProvider(),
        createQoderProvider(),
        createVeniceProvider(),
        createNousProvider(),
        createMuseProvider(),
        createDeepgramProvider(),
        createClinePassProvider(),
        createCrofProvider(),
        createSyntheticProvider(),
        createClawRouterProvider(),
        createLiteLLMProvider(),
        createLLMProxyProvider(),
        createElevenLabsProvider(),
        createFireworksProvider(),
        createNeuralWattProvider(),
        createIBMBobProvider(),
        createAiAndProvider(),
        createCodebuffProvider(),
        createSub2ApiProvider(),
        createDevinProvider(),
        createAbacusProvider(),
        createCommandCodeProvider(),
        createLongCatProvider(),
        createZoomMateProvider(),
        createNotionProvider(),
        createHuggingFaceProvider(),
        createWarpProvider(),
        createOpenCodeProvider(),
        createOpenCodeGoProvider(),
        createGroqProvider(),
        createAlibabaCodingPlanProvider(),
        createFactoryProvider(),
        createDoubaoProvider(),
        createV0Provider(),
        createAmpProvider(),
        createAzureOpenAIProvider(),
        createOllamaProvider(),
        createCopilotProvider(),
        createBedrockProvider(),
        createDemoProvider(),
      ];
    }
    return ProviderRegistry.providers;
  }

  static byId(id: string): UsageProvider | null {
    const list = ProviderRegistry.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].descriptor.id === id) {
        return list[i];
      }
    }
    return null;
  }

  static descriptors(): ProviderDescriptor[] {
    return ProviderRegistry.all().map(p => p.descriptor);
  }
}

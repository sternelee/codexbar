/**
 * CodexBar Mobile — 服务商品牌图标
 * 彩色 SVG 来源：lobehub/lobe-icons（MIT）。图标渲染在白色圆角衬底上，
 * 保证深色主题下单色品牌标（OpenAI/xAI 等）的可见性；
 * 无对应品牌图的服务商回退为强调色圆点。
 *
 * 衬底在明亮/暗色下都保持白色（白底才能托住 OpenAI、Bedrock 这类白/黑单一色的标），
 * 明亮模式下靠一圈 `icon_plate_edge` 描边与白色卡片区分。
 */

import { Theme } from '../common/Theme';

/** providerId → rawfile 图标文件名 */
export function iconFileFor(providerId: string): string | null {
  switch (providerId) {
    case 'claude':
    case 'anthropic-console':
      return 'claude-color.svg';
    case 'codex':
    case 'openai':
      return 'openai.svg';
    case 'openrouter':
      return 'openrouter-color.svg';
    case 'deepseek':
      return 'deepseek-color.svg';
    case 'moonshot':
      return 'moonshot.svg';
    case 'kimi-coding':
      return 'kimi-color.svg';
    case 'siliconflow':
      return 'siliconcloud-color.svg';
    case 'zenmux':
      return 'zenmux.svg';
    case 'manus':
      return 'manus.svg';
    case 'deepinfra':
      return 'deepinfra-color.svg';
    case 'perplexity':
      return 'perplexity-color.svg';
    case 'minimax':
      return 'minimax-color.svg';
    case 'mimo':
      return 'xiaomimimo.svg';
    case 'mistral':
      return 'mistral-color.svg';
    case 'kilo':
      return 'kilocode.svg';
    case 'poe':
      return 'poe-color.svg';
    case 'zai':
      return 'zhipu-color.svg';
    case 'xai':
      return 'xai.svg';
    case 'qoder':
      return 'qoder-color.svg';
    case 'venice':
      return 'venice-color.svg';
    case 'nous':
      return 'nousresearch.svg';
    case 'muse':
      return 'meta-color.svg';
    case 'clinepass':
      return 'clinepass.svg';
    case 'clawrouter':
      return 'clawrouter.svg';
    case 'opencode':
    case 'opencodego':
      return 'opencode.svg';
    case 'llmproxy':
      return 'llmapi-color.svg';
    case 'litellm':
      return 'litellm.svg';
    case 'elevenlabs':
      return 'elevenlabs.svg';
    case 'fireworks':
      return 'fireworks-color.svg';
    case 'neuralwatt':
      return 'neuralwatt.svg';
    case 'ibmbob':
      return 'ibm.svg';
    case 'devin':
      return 'devin-color.svg';
    case 'abacus':
      return 'abacus.svg';
    case 'commandcode':
      return 'commandcode.svg';
    case 'longcat':
      return 'longcat.svg';
    case 'zoommate':
      return 'zoommate.svg';
    case 't3chat':
      return 't3chat.svg';
    case 'factory':
      return 'factory.svg';
    case 'notion':
      return 'notion.svg';
    case 'azure-openai':
      return 'openai.svg';
    case 'huggingface':
      return 'huggingface-color.svg';
    case 'warp':
      return 'warp.svg';
    case 'chutes':
      return 'chutes.svg';
    case 'codebuff':
      return 'codebuff.svg';
    case 'deepgram':
      return 'deepgram.svg';
    case 'sub2api':
      return 'sub2api.svg';
    case 'synthetic':
      return 'synthetic.svg';
    case 'aiand':
      return 'aiand.svg';
    case 'alibaba-coding':
      return 'alibaba.svg';
    case 'groq':
      return 'groq.svg';
    case 'v0':
      return 'v0.svg';
    case 'amp':
      return 'amp.svg';
    case 'ollama':
      return 'ollama.svg';
    case 'bedrock':
      return 'bedrock.svg';
    case 'copilot':
      return 'copilot.svg';
    case 'doubao':
      return 'doubao-color.svg';
    default:
      return null;
  }
}

@Component
export struct ProviderIcon {
  providerId: string = '';
  /** 品牌强调色（hex）；极端色值由 Theme.brandTint 回落到应用主色 */
  accentColor: string = '';
  /** 图标尺寸（衬底边长） */
  iconSize: number = 32;

  build() {
    if (iconFileFor(this.providerId) != null) {
      Row() {
        Image($rawfile(`icons/${iconFileFor(this.providerId)}`))
          .width(this.iconSize * 0.62)
          .height(this.iconSize * 0.62)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(this.iconSize)
      .height(this.iconSize)
      .borderRadius(this.iconSize * 0.3)
      .backgroundColor(Theme.iconPlate)
      .border({ width: 1, color: Theme.iconPlateEdge })
    } else {
      Row()
        .width(this.iconSize * 0.38)
        .height(this.iconSize * 0.38)
        .borderRadius(this.iconSize * 0.19)
        .backgroundColor(Theme.brandTint(this.accentColor))
    }
  }
}

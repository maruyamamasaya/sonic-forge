# 0015: 交換可能なAI演奏生成と検証済み候補の採用

Date: 2026-10-17

## Context
演奏スキルなしで言葉から演奏を作りたい。OpenAI APIに加え、利用者はCodex CLI・他のAIも希望する。

## Decision
共通の演奏JSON v1を境界とし、Codex CLI・OpenAI Responses・外部AI貼り付けを同じ検証へ通す。確認用DemoはAIと明確に分ける。候補段階では既存演奏を変更せず、明示採用後に既存CoreMIDI経路へ渡す。4小節に限定し、原音は送らない。設定・制約は[AI生成](../AI_GENERATION.md)。

## Alternatives
自由形式のコード/生MIDI生成は検証と停止の範囲を広げるため採用しない。特定のAIへの固定は利用者の希望と合わない。TypeScript SDK/サーバー追加はnativeアプリの今回の機能には不要。OpenAIのAPIキーは埋め込み・永続化せず個人のセッション内入力とする。

## References
[OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)、[GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini)、[Codex非対話実行](https://learn.chatgpt.com/docs/non-interactive-mode)。実装前に公式資料とローカルcodex exec --helpで引数を確認。

## Consequences
ネットワーク・CLIログイン・API利用枠が必要。Demoだけの成功は実AIの成功ではない。他プロバイダー直結は今後のadapter追加で扱い、現時点では貼り付けで利用する。

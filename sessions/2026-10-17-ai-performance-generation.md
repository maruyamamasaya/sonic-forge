# 言葉からのAI演奏生成

Date: 2026-10-17

## Request
言葉の指示から作った楽器で演奏できるデータを生成。既存UIを維持し、デモ確認とAI向け文書を更新。接続先としてOpenAI API・他のAI・Codex CLIを希望。

## Changes
Compose画面・候補ピアノロール・明示採用・未保存演奏の置換確認を追加。Codex CLI、OpenAI Responses、外部AI JSON貼り付け、AIとは区別したDemoを共通形式検証へ接続。生成候補は4小節・64音符。原音は送らない。既存のCoreMIDI自動演奏・編集・保存へ接続し、ガイドと[判断0015](../decisions/0015-ai-performance-generation.md)を更新。

## Validation
Fast・最終Full（通常テスト・アプリビルド）成功。模擬HTTPとCLI fixtureを含む--playback成功。実Codex CLIで生成→検証→保存→再読込→デモ楽器発音成功（明示--ai-live）。OpenAI APIは模擬応答の検証のみ、実キーでの接続は未実行。

実UIでもCodex CLIから「静かな和音」（16音符・68 BPM・8ペダルイベント）を生成し、候補ピアノロール→Use & Play→4音/実メーター→自然終了で0音・ペダルOFFを確認。Edit→保存、未保存変更の置換Cancel、Other AI JSON検証、OpenAIキー未設定エラーも確認。幅約1000の本体・生成シートの表示を確認。最終ビルドでも32音符のBouncyデモを採用→Softデモ楽器で発音・実メーター→All Notes Offで0音・無音を確認。
ビルド初回は制限環境のiconutilで失敗、再実行時に編集中ファイルの変更を検知。ソース確定後の権限付きビルド・Fullは成功。

## Result
接続方式を切り替えて演奏JSON候補を作成・採用可能。実AIの成功とDemoの成功を区別する。

## Remaining Issues
他社API直結、音色解析、曲全体の編曲、生成履歴の永続化は未実装。生成の音楽性はユーザーフィードバックで改善する。

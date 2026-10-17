# 0035: 音声を含まない編曲提案と明示的な採用

## Context
単一フレーズのAI生成から、既存のサンプラー楽器を使った複数パート/セクションの構成へ進む。外部出力を直接既存モデルへ書くと、途中失敗や古い応答で構成を壊す。

## Decision
音声なしのArrangementProposal v1を導入し、既存partIDと新セクションの整数indexだけを参照する。共通schema/演奏検証/EnsembleClips/EnsembleDocumentで全候補を値検証後、revision一致時に明示的な採用で一括反映する。生成中は既存構成を変えない。接続4方式は共有し、既存Foundation/ProcessのJSON通信だけを共通化する。楽器とMasterは保持。採用は全配置/パートmix置換で、音符単位履歴はクリアする。操作正本は[AI_ARRANGEMENT.md](../AI_ARRANGEMENT.md)。

## Alternatives
.sfensemble全体をAIへ送る方式は音声転送と不要なデータ変更が生じる。逐次パッチは途中状態/重複/参照処理が複雑なため初回は採らない。楽器や素材をAIが増やす操作、全構成のUndo、採用前の音声試聴は別機能として保留。元構成は先に保存して保持できる。

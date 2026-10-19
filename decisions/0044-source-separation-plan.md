# 0044: 音源分離の初期実装方針
Date: 2026-10-19
Status: superseded

実機比較とbackend採用は[0045](0045-mlx-separation-backend.md)で確定。以下は比較前の提案記録。

## Context
[全体構想](../ROADMAP.md)の次の到達点として、1曲の分離結果から使える短い音を選び、楽器として保存する。ユーザーはまず技術調査と実装方針の整理を依頼した。現在のアプリはSwiftUI/AVFoundation、第三者の推論依存なし。

## Decision
提案として、ローカルDemucs系htdemucsの4ステムを最初の範囲にし、専用Python環境のworkerを別プロセスで呼ぶ。元のPyTorch実装を比較基準にdemucs-mlxを実機評価し、条件を満たしたbackendと依存を固定する。結果WAVを現在のSample Studioへ渡し、既存の範囲選択・楽器化・音源同梱保存を再利用する。バックエンドの採用・導入はまだ行わない。

## Reason
1曲から楽器保存までの制作体験を小さく検証し、重い推論の取消・失敗・メモリをUI/演奏から分離する。将来の対象別モデルやネイティブ実装へ交換できる境界を先に設ける。

## Alternatives
python-audio-separator/RoFormerは対象別品質向上の候補。Swift/Metal/Core ML統合は導入・配布方式と移植品質の検証を伴う。SAM Audioのプロンプト分離は将来像に適するがMacでの資源・動作を未確認。クラウド分離は初期案に含めない。

## Consequences
既存のApple標準アプリに任意の外部推論環境が加わる。モデル・コード・依存の版と取得元を管理する必要がある。4ステムは全楽器・SEの個別抽出を保証しない。実機品質・速度・メモリ・オフライン・停止の確認後に採用判断を更新する。詳細と一次資料は[音源分離方針](../SOURCE_SEPARATION.md)を正本とする。

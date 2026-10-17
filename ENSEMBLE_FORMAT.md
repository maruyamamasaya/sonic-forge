# 構成ファイル形式 v1

正本は[EnsembleDocument.swift](app/EnsembleDocument.swift)。操作は[ENSEMBLE.md](ENSEMBLE.md)。UTF-8 JSON、拡張子.sfensemble、最大384 MiB。音源同梱で外部パスへ依存しない。

## フィールド
全フィールド必須。未知のversionを拒否する。

| 場所・フィールド | 内容 |
| --- | --- |
| version | 整数1 |
| tempo | 共通テンポ、有限数40〜240 BPM |
| masterDB | Ensemble共通Master、有限数−60〜0 dB |
| parts | 順序付き1〜4パート |
| parts[].name | パート名、1〜80文字、空白のみ不可 |
| parts[].instrumentName | 楽器の表示名、最大255文字 |
| parts[].instrument | InstrumentArchiveの楽器オブジェクト（書込時v4）を直接格納。基準音・ADSR・ループ・クロスフェード・音源名とbase64 WAVを含む |
| parts[].performance | [演奏形式v1](PERFORMANCE_FORMAT.md)のオブジェクト。元のtempoも保持し、再生時のみ共通tempoを優先 |
| parts[].gainDB | パート音量、有限数−36〜0 dB |
| parts[].muted | 真偽値 |

楽器形式の正本は[InstrumentDocument.swift](app/InstrumentDocument.swift)のInstrumentArchive/makeArchive/restore。同梱WAVはPCM Float32、サンプル上限64 MiBとWAVヘッダー分。各楽器は既存のv1〜v4読み込み検証を共有する。基準音48〜72、最大30秒・デコード後64 MiB、全ADSR/ループ制限を満たす必要がある。
保存前と読込時に各演奏の形式・重複・保持8音以内・ペダル終端・楽器Root±24半音を検証する。ミュートしたパートも検証対象。AI生成専用の16拍/64音符制限を構成全体へ追加せず、通常の演奏形式の範囲を使う。

## 保存・復元の境界
検証と全エンコードが成功した後、atomic writeで保存する。不正な保存では既存ファイルを変更しない。読み込みでは全パートが成功してから現在のモデルを置き換え、後半パートの破損でも部分反映しない。
ファイル内に原本パス・実行コード・認証情報・再生位置・発音数・押鍵/ペダルの現在状態は保存しない。各パートのUUIDは読み込み時に新規作成する。再生するペダルイベントはperformanceに含まれるが、復元時点でペダルを踏んだ状態にはしない。
最後に正常保存/読込したパスだけをアプリのUserDefaults（lastEnsemblePathV1）で記憶する。構成を別のMacへ移す場合は.sfensemble単体をコピーしてOpen…すればよい。移動後の自動パス追跡・クラウド同期・未保存変更の自動復旧は未実装。

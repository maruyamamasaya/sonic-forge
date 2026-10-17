# 構成ファイル形式 v4

正本は[EnsembleDocument.swift](app/EnsembleDocument.swift)。操作は[ENSEMBLE.md](ENSEMBLE.md)。UTF-8 JSON、拡張子.sfensemble、最大384 MiB。音源同梱で外部パスへ依存しない。

## フィールド
v4はsectionsが必須、parts[].sectionIDは省略/nullでSong。v1〜v3も読み込み可能でセクションなし、v1/v2は繰り返し回数1、v1の開始位置は0へ移行。保存は常にv4。未知のversionを拒否する。

| 場所・フィールド | 内容 |
| --- | --- |
| version | 整数4（読込は1/2/3も可） |
| tempo | 共通テンポ、有限数40〜240 BPM |
| masterDB | Ensemble共通Master、有限数−60〜0 dB |
| parts | 順序付き1〜4パート |
| parts[].name | パート名、1〜80文字、空白のみ不可 |
| parts[].instrumentName | 楽器の表示名、最大255文字 |
| parts[].instrument | InstrumentArchiveの楽器オブジェクト（書込時v4）を直接格納。基準音・ADSR・ループ・クロスフェード・音源名とbase64 WAVを含む |
| parts[].performance | [演奏形式v1](PERFORMANCE_FORMAT.md)のオブジェクト。元のtempoも保持し、再生時のみ共通tempoを優先 |
| parts[].gainDB | パート音量、有限数−36〜0 dB |
| parts[].muted | 真偽値 |
| sections | v4必須、順序付き0〜8個の{id: UUID, name: 非空白1〜40文字, beats: 有限数1〜256}。ID重複不可 |
| parts[].sectionID | sections内のUUID、または省略/nullで曲頭基準。未知参照は拒否 |
| parts[].repeatCount | v3必須、整数1〜16。追加回数ではなく合計演奏回数 |
| parts[].startBeat | v2必須、有限数0〜256拍。小数可。曲頭からの待機拍数 |

楽器形式の正本は[InstrumentDocument.swift](app/InstrumentDocument.swift)のInstrumentArchive/makeArchive/restore。同梱WAVはPCM Float32、サンプル上限64 MiBとWAVヘッダー分。各楽器は既存のv1〜v4読み込み検証を共有する。基準音48〜72、最大30秒・デコード後64 MiB、全ADSR/ループ制限を満たす必要がある。
保存前と読込時に各演奏の形式・重複・保持8音以内・ペダル終端・楽器Root±24半音を検証する。ミュートしたパートも検証対象。AI生成専用の16拍/64音符制限を構成全体へ追加せず、通常の演奏形式の範囲を使う。

## 保存・復元の境界
検証と全エンコードが成功した後、atomic writeで保存する。不正な保存では既存ファイルを変更しない。読み込みでは全パートが成功してから現在のモデルを置き換え、後半パートの破損でも部分反映しない。
ファイル内に原本パス・実行コード・認証情報・再生位置・発音数・押鍵/ペダルの現在状態は保存しない。各パートのUUIDは読み込み時に新規作成する。再生するペダルイベントはperformanceに含まれるが、復元時点でペダルを踏んだ状態にはしない。
最後に正常保存/読込したパスだけをアプリのUserDefaults（lastEnsemblePathV1）で記憶する。構成を別のMacへ移す場合は.sfensemble単体をコピーしてOpen…すればよい。移動後の自動パス追跡・クラウド同期・未保存変更の自動復旧は未実装。

startBeatはperformance内のbeatを書き換えず、再生時に全イベントの秒へstartBeat × 60 / 共通tempoを加える。v2の欠落/null・負数・上限超過は拒否する。旧アプリはv4を拒否するため、上書き後は旧版で開けない。

repeatCountは元のperformanceを複製して保存せず、再生/出力時に展開する。各回の間隔は元の最終イベント拍のceil、全体長は(count−1)×間隔＋元の長さ。正本は[EnsembleTimeline.swift](app/EnsembleTimeline.swift)のevents/repeatedLength。

セクションは配列順に隙間なく連結する。part.startBeatは割り当て先内の相対拍。繰り返し込みの演奏終端がセクションのbeatsを超える場合は拒否。Songパートは従来の曲頭基準。曲長は全セクション合計と全イベント終端の大きい方で、空のセクションも含む。正本は[EnsembleSections.swift](app/EnsembleSections.swift)。

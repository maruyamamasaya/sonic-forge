# 構成ファイル形式 v10

正本は[EnsembleDocument.swift](app/EnsembleDocument.swift)。操作は[ENSEMBLE.md](ENSEMBLE.md)。UTF-8 JSON、拡張子.sfensemble、最大384 MiB。音源同梱で外部パスへ依存しない。

## フィールド
v5はsectionsと各パートのadditionalClipsが必須。sectionIDは省略/nullでSong。v1〜v4は追加クリップなしへ移行し、v1〜v3はセクションなし、v1/v2は繰り返し回数1、v1の開始位置は0へ移行。v6は各パートのpanも必須。v1〜v5のpanは中央0へ移行。v7はeqも必須。v1〜v6のEQはフラットへ移行。v8はreverbも必須。v1〜v7はリバーブ0へ移行。v9はdelayも必須。v1〜v8はディレイオフへ移行。v10はcompressorも必須。v1〜v9はコンプレッサーオフへ移行。保存は常にv10。未知のversionを拒否する。

| 場所・フィールド | 内容 |
| --- | --- |
| version | 整数10（読込は1〜9も可） |
| tempo | 共通テンポ、有限数40〜240 BPM |
| masterDB | Ensemble共通Master、有限数−60〜0 dB |
| parts | 順序付き1〜4パート |
| parts[].name | パート名、1〜80文字、空白のみ不可 |
| parts[].instrumentName | 楽器の表示名、最大255文字 |
| parts[].instrument | InstrumentArchiveの楽器オブジェクト（書込時v4）を直接格納。基準音・ADSR・ループ・クロスフェード・音源名とbase64 WAVを含む |
| parts[].performance | [演奏形式v1](PERFORMANCE_FORMAT.md)のオブジェクト。元のtempoも保持し、再生時のみ共通tempoを優先 |
| parts[].gainDB | パート音量、有限数−36〜0 dB |
| parts[].muted | 真偽値 |
| parts[].pan | v6必須、有限数−1〜1。−1=左、0=中央、1=右。パートの全クリップで共通 |
| parts[].eq | v7必須、{lowDB, midDB, highDB}。各値は有限数−12〜12 dB。0はフラット、全クリップ共通 |
| parts[].reverb | v8必須、有限数0〜100%。0はオフ、小さな部屋のwet/dry。全クリップ共通 |
| parts[].delay | v9必須、{timeMS, mix, feedback}。有限数50〜1000 ms / 0〜100% / 0〜60%。既定300/0/35。mix=0でオフ、全クリップ共通 |
| parts[].compressor | v10必須、{enabled: Bool, thresholdDB, headroomDB, attackMS, releaseMS, makeupDB}。有限数−40〜0 dB / 0.1〜40 dB / 0.1〜200 ms / 10〜3000 ms / 0〜24 dB。既定false/−24/5/10/150/0。全クリップ共通 |
| sections | v4必須、順序付き0〜8個の{id: UUID, name: 非空白1〜40文字, beats: 有限数1〜256}。ID重複不可 |
| parts[].sectionID | sections内のUUID、または省略/nullで曲頭基準。未知参照は拒否 |
| parts[].additionalClips | v5必須、0〜7個のEnsembleClip。最初の演奏は従来のperformance/startBeat/repeatCount/sectionIDで保持 |
| additionalClips[].id | 安定UUID、同じパートの追加クリップ間で重複不可 |
| additionalClips[].performance | 通常の演奏形式v1 |
| additionalClips[].startBeat / repeatCount | 有限数0〜256拍 / 整数1〜16、必須 |
| additionalClips[].sectionID | 既存セクションのUUID、または省略/nullでSong |
| parts[].repeatCount | v3必須、整数1〜16。追加回数ではなく合計演奏回数 |
| parts[].startBeat | v2必須、有限数0〜256拍。小数可。曲頭からの待機拍数 |

楽器形式の正本は[InstrumentDocument.swift](app/InstrumentDocument.swift)のInstrumentArchive/makeArchive/restore。同梱WAVはPCM Float32、サンプル上限64 MiBとWAVヘッダー分。各楽器は既存のv1〜v4読み込み検証を共有する。基準音48〜72、最大30秒・デコード後64 MiB、全ADSR/ループ制限を満たす必要がある。
保存前と読込時に各演奏の形式・重複・保持8音以内・ペダル終端・楽器Root±24半音を検証する。ミュートしたパートも検証対象。AI生成専用の16拍/64音符制限を構成全体へ追加せず、通常の演奏形式の範囲を使う。

## 保存・復元の境界
検証と全エンコードが成功した後、atomic writeで保存する。不正な保存では既存ファイルを変更しない。読み込みでは全パートが成功してから現在のモデルを置き換え、後半パートの破損でも部分反映しない。
ファイル内に原本パス・実行コード・認証情報・再生位置・発音数・押鍵/ペダルの現在状態は保存しない。各パートのUUIDは読み込み時に新規作成する。再生するペダルイベントはperformanceに含まれるが、復元時点でペダルを踏んだ状態にはしない。
最後に正常保存/読込したパスだけをアプリのUserDefaults（lastEnsemblePathV1）で記憶する。構成を別のMacへ移す場合は.sfensemble単体をコピーしてOpen…すればよい。移動後の自動パス追跡・クラウド同期・未保存変更の自動復旧は未実装。

startBeatはperformance内のbeatを書き換えず、再生時に全イベントの秒へstartBeat × 60 / 共通tempoを加える。v2の欠落/null・負数・上限超過は拒否する。v9までの旧アプリはv10を拒否するため、上書き後は旧版で開けない。

repeatCountは元のperformanceを複製して保存せず、再生/出力時に展開する。各回の間隔は元の最終イベント拍のceil、全体長は(count−1)×間隔＋元の長さ。正本は[EnsembleTimeline.swift](app/EnsembleTimeline.swift)のevents/repeatedLength。

セクションは配列順に隙間なく連結する。part.startBeatは割り当て先内の相対拍。繰り返し込みの演奏終端がセクションのbeatsを超える場合は拒否。Songパートは従来の曲頭基準。曲長は全セクション合計と全イベント終端の大きい方で、空のセクションも含む。正本は[EnsembleSections.swift](app/EnsembleSections.swift)。

最初の演奏と追加クリップを合わせて1〜8個。全演奏を同じ楽器Rootで検証し、セクション範囲と同一パート内の時間的重複を拒否する。音源とmixはパートに一度だけ格納し、追加クリップ内へ音源や外部パスを保存しない。最初のクリップのUI用IDは復元時に新規生成し、追加クリップIDはファイルから復元。正本は[EnsembleClips.swift](app/EnsembleClips.swift)。

# 複数パート・セクションの編曲提案

## 操作入口
Ensemble中央上部のAI編曲…を開く。既存の1〜4パートすべてへ楽器を割り当て、有効な構成で停止してから使う。空なら先にデモ曲を追加する。候補を生成は現在の楽器/演奏を参照して、曲全体のセクション・クリップ・共通テンポ・パート音量/Muteを提案する。新しい楽器の生成・音源分離・音色解析は行わない。
接続は既存AI演奏…と同じ設定を共有する。Codex CLI / OpenAI API / Other AI / Demoの準備は[AI生成の接続方式](AI_GENERATION.md#接続方式)。OpenAIはResponses APIのstrict JSON Schemaを使う（[公式仕様](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)）。本アプリはSwiftのためTypeScript AI SDKは使用しない。

## 確認と採用
生成結果の方式・タイトル・説明・BPM・拍数・変更前後のセクション/クリップ数、提案タイムラインを確認する。各パートに音量/Mute、各クリップに音符数・繰り返し・相対開始拍と実音符を表示する。空のセクションセルはそのパートが演奏しない区間。ペダル/Releaseの余韻はバーの音符長に含めない。
この編曲案を採用で候補全体を採用し、メインのタイムラインへ戻る。未保存変更がある場合は編曲案で置き換えるで置換を確認する。元を別バージョンとして残すならキャンセル→現在の構成を保存…で先に保存する。採用時に元の全セクション/クリップ/テンポ/パートmixを置き換え、音符Undo/Redo履歴をクリアする。楽器PCM/Root/ADSR/Loop・パート名/ID・Master・保存先は保持し、dirty=trueにする。自動再生/自動保存はせず、全体を再生で確認して別名保存できる。採用を含む構成全体の取り消し/やり直しは、タイムライン上段の専用矢印から1操作で行える。履歴は直近50操作・セッション内のみ。詳しくは[曲全体の履歴](ENSEMBLE.md#曲全体の取り消しやり直し)。
生成・検証・失敗・生成を中止・閉じるでは現在の構成を変更しない。方式/モデル/CLIパス/指示/JSON変更やシート閉鎖で候補を破棄。生成中または生成後に元構成が変わった場合は古い候補を採用せず、再生成を案内する。生成中に現在の構成を保存…は使えない。再生/保存/書き出し中は生成・採用不可。停止は既存全停止。生成取消は再生停止とは別操作。

## AIへ送信する情報
指示と現在の共通テンポ、セクション名/ID/長さ、パート名/実行時ID/Root/音量/Mute、各クリップの配置・演奏音符/ペダルを送る。音声PCM・楽器ファイル名・原本パス・保存先・APIキーを音楽コンテキストへ含めない。音色を聴いて提案する機能ではない。Other AIは指示をコピーを押したときだけコンテキストとschemaをOSクリップボードへコピーし、利用者が手動で渡す。パート名や指示に送信したくない情報を含めない。
OpenAIの接続先固定・store=false・リダイレクト禁止・キーのメモリ保持・HTTPエラー/未完了/refusal拒否・応答1 MB上限は既存経路と共通。編曲の出力枠は16000トークン、CLIは既存120秒制限。外部出力のコード/コマンドを実行しない。CLIは既存の空一時領域・read-only・個人設定不使用・ツール無効で起動する。

## 編曲提案JSON v1
保存済みの.sfensembleとは別の、音声を含まない一時提案形式。JSON Schemaの正本はArrangementGeneration.schema。指示をコピーで現在のpartIDと完全なschemaを取得する。提案ファイルの読み書きUIはなく、Other AI欄への貼り付けで検証する。採用後は既存.sfensemble v10へ保存する。

| フィールド | 意味・検証 |
| --- | --- |
| version/name/summary | 1、名前1〜80文字、説明1〜1000文字 |
| tempo | 共通40〜240 BPM |
| sections | 配列順、1〜8個、name 1〜40文字・beats 1〜64、全体256拍以下 |
| parts | 既存partIDを各1回、追加/欠落/重複不可。配列順に依存せず元のパート順へ解決 |
| parts[].gainDB/muted | 音量−36〜0 dB、Mute。Masterは提案対象外 |
| parts[].clips | 各1〜8個。演奏しないセクションにはクリップを置かない |
| clips[].sectionIndex | 新しいsections配列の0始まり整数。旧section UUIDではない |
| clips[].startBeat/repeatCount | セクション内開始0〜256拍、1〜16回。セクション内に収まること。同一パートの区間重複不可 |
| clips[].performance | [演奏形式v1](PERFORMANCE_FORMAT.md)。各16拍/64音符以内、案全体512音符以下。Root±24、同音重複/8音超過/未解除ペダル等は既存検証 |

提案指示ではtranspose=0、velocityPercent=100、MIDI channel=0、演奏tempo=共通tempoを求める。検証は既存演奏形式も許容し、実再生は共通tempoを優先する。繰り返し間隔はceil(最後の音符/ペダルの拍)、配置検証は既存EnsembleClipsと同じ。

## デモと状態判定
Demo→「薄いイントロ → 厚いサビ」→デモ案を作る。Intro 8拍は先頭パートの単音、Aメロ16拍で先頭2パート、サビ16拍で全パートと和音を配置する。1パートでも1音→2音→3音の差を確認できる。「均一な構成」（またはevenを含む指示）は全パートを全セクションへ配置する別の固定例。自由な指示の意味理解は実AI方式で行う。Demoはプログラムによる例でありAI応答ではない。
生成中はArrangementComposer.generating、成功はcandidate/preview/briefがありerror=nil。採用成功は候補が消えてシートが閉じ、EnsembleModel.dirty=true。保存・復元・WAV出力・停止の判定は[AI操作ガイド](AI_OPERATIONS.md)を使う。接続未実施の方式を検証済みと報告しない。

## 実装入口
WorkspaceViewのAI編曲…→ArrangementComposerView→ArrangementComposer.generate/cancel/adopt。ArrangementBriefは現在構成とrevisionを固定し音声なしの指示を作る。ArrangementGeneration.decode/materializeが候補値を全検証し、EnsembleModel.applyArrangementがrevision照合後に一括反映する。外部から呼べるAPIではない。共有JSON通信はCodexPerformanceClient.generateJSON / OpenAIPerformanceClient.jsonRequest/generateJSONで、従来の短い演奏生成も同じ処理を使う。

手動のパン（左右配置）は編曲案の対象外で、採用時も元の値を保持します。構成保存v10とWAVにはパンを含めます。

手動の3バンドEQも編曲案の対象外で、materialize/採用時に元の設定を保持する。構成v10とWAVに反映する。

手動のリバーブ量も提案schemaの対象外。候補materialize/採用時に元のパート設定を保持し、構成v10とWAVへ反映する。

手動のディレイ3値も提案schemaの対象外。materialize/採用時に元の値を保持し、構成v10と全体WAVへ反映する。

コンプレッサーもmaterialize時に既存パートの手動値を保持する。提案/briefのschemaは変更せず、操作と停止は[AI操作](AI_OPERATIONS.md#パートのコンプレッサーを調整する)を参照。

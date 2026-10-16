# コードと情報の地図

## 現在の入口
| 目的 | 主なファイル | 検索キーワード |
| --- | --- | --- |
| コンセプト・人間向け案内 | README.md | SonicForge、音 |
| 現在地・次の作業 | CURRENT.md | 未実装、次に行うこと |
| AI演奏生成 | AI_GENERATION.md | Compose、Codex CLI、OpenAI API、Demo |
| 演奏ファイル仕様 | PERFORMANCE_FORMAT.md | version、tempo、transpose、notes、pedals |
| AIによる操作・演奏 | AI_OPERATIONS.md | 操作とアプリ内の入口、成功判定、演奏データ |
| AI作業規則 | AGENTS.md | 開始時、終了時 |
| 実装構成 | ARCHITECTURE.md | Technology、API、Database |
| 検証 | TESTING.md | 検証、未整備 |
| 開発・運用 | OPERATIONS.md | Local、Environment、Deploy |
| Git除外設定 | .gitignore | .env、dist、build |
| 設計判断 | decisions/ | Context、Decision |
| 作業履歴 | sessions/ | Request、Validation |

## アプリケーションコード
| Feature | Primary paths | Search keywords / Key entry points | Related tests |
| --- | --- | --- | --- |
| アプリ入口・起動時デモ | app/SonicForgeApp.swift | SonicForgeApp、Window、loadDemo | 実アプリ手動確認 |
| WAV・デモ・波形解析 | app/AudioAsset.swift | AudioAsset.load、DemoAudio.write、peaks | tests/AudioTests.swift |
| 再生・ファイル選択・状態 | app/PlayerModel.swift | open、load、toggle、stop、seek、playSelection、refreshPlaybackState | tests/AudioTests.swift --playback |
| 選択・ズーム・表示範囲 | app/WaveformEditor.swift | select、setZoom、pan、fitSelection、AudioSelection | tests/AudioTests.swift |
| 選択区間の音声 | app/SelectionAudio.swift | SelectionAudio.write、framePosition、frameCount | tests/AudioTests.swift |
| WAV書き出し | app/WAVExport.swift、app/PlayerModel.swift | WAVExport.write、exportSelection、export、NSSavePanel | tests/AudioTests.swift |
| 楽器ライブラリ | app/InstrumentLibrary.swift、app/LibraryView.swift | register、add、addDemos、filtered、preview、stopPreview | tests/LibraryTests.swift / --playback |
| 楽器保存・復元 | app/InstrumentDocument.swift、app/PlayerModel.swift | InstrumentDocument.save/load、saveInstrument、loadInstrument、startSession、instrumentDirty | tests/AudioTests.swift / --playback |
| サンプルループ | app/SampleInstrument.swift、app/PlayerModel.swift、app/InstrumentKeyboard.swift | SampleLoop.crossfadeFrames、InstrumentVoice.render、loopFromSelection、LoopControls | tests/EnvelopeTests.swift、tests/AudioTests.swift |
| ADSR | app/ADSREnvelope.swift、app/SampleInstrument.swift、app/InstrumentKeyboard.swift | ADSRParameters、ADSREnvelope.next、InstrumentVoice.render、EnvelopeControls、setEnvelope | tests/EnvelopeTests.swift、tests/AudioTests.swift --playback |
| 言葉から演奏生成 | app/PerformanceGeneration.swift、app/CodexPerformanceClient.swift、app/PerformanceComposer.swift、app/PerformanceComposerView.swift | PerformanceBrief、schema、decodeResponse、generate、cancel、applyGeneratedPerformance | tests/GenerationTests.swift / --playback / --ai-live |
| 演奏編集・保存 | app/PerformanceDocument.swift、app/PerformanceEditor.swift、app/MIDIInput.swift | PerformanceDocument.load/save/events、loadPerformance、performanceDirty | tests/PerformanceTests.swift / --playback |
| 外部MIDI | app/MIDIInput.swift、app/PlayerModel.swift、app/InstrumentKeyboard.swift | MIDIInput.select/refresh、MIDIByteParser、MIDIReceiver、receiveMIDI、setMIDISustain、MIDIPerformancePreset、playPerformance、MIDIControls | tests/MIDITests.swift / --playback |
| 和音楽器・音程 | app/SampleInstrument.swift、app/PlayerModel.swift | InstrumentSample.load、NotePitch.rate、SampleInstrument.Slot、heldNotes、playNote、releaseNote、synchronizeNotes、computerKeyboard | tests/AudioTests.swift / --playback |
| 画面鍵盤・基準音 | app/InstrumentKeyboard.swift | InstrumentKeyboard、Root note、Use Selection | 実UI確認 |
| UI・波形・メーター | app/StudioView.swift | StudioView、WaveCanvas、StudioButton、OutputMeterColumn、OutputMeterState | 実アプリ手動確認 |
| アプリアイコン | app/Resources/AppIcon.png、scripts/build.sh | AppIcon、iconutil、CFBundleIconFile | Full + ICNS・署名確認 |
| ビルド・テスト | scripts/build.sh、scripts/test.sh | swiftc、AudioTests、codesign | 標準Verify |

app配下の追加ルールは [app/AGENTS.md](app/AGENTS.md)。外部操作API・DB・認証は未実装。AI生成接続は[AI_GENERATION.md](AI_GENERATION.md)。

## 検証基盤
- Feature: 文書・アプリ自動検証
- Primary paths: `scripts/verify.py`
- Search keywords: `check_documents`、`CORE`、`--fast`
- Key entry points: `main` → `check_documents`
- Related tests: 専用テストスイートは未整備。検証方法と限界は [TESTING.md](TESTING.md)。

今後の機能もFeature / Primary paths / Search keywords / Key entry points / Related testsを短く追記する。

## 検索方法
| 分かっていること | 優先する探索 |
| --- | --- |
| 概念だけ | 利用可能ならsemantic / repository search。なければ概念の同義語で範囲を絞る |
| 関数・クラス名 | symbol / exact searchで定義を特定 |
| 特定文字列・環境変数・エラー | rg / git grepの完全一致検索 |
| 呼び出し元・影響範囲 | references searchと関連テスト検索。なければシンボル名を横断検索 |

semantic検索やインデックスの設定はリポジトリ内にない。実行環境で利用可能かを確認し、導入を前提にしない。検索結果は候補であり、正確なシンボル・パスが分かったらexact / symbolへ切り替え、実ファイルで裏付ける。インデックスの鮮度・未追跡ファイルの収録範囲にも注意する。
対象を絞った後、定義・参照・テスト・設定・データ依存と、対象へ適用されるAGENTS.mdを確認する。

```sh
rg --files --hidden -g '!.git/**'
rg -n -F '検索する関数名' .
rg -n 'TODO|FIXME' .
git grep -n '検索語'
```

rgは通常隠しファイルや除外対象を省く。.gitignoreなどは必要に応じ明示して読む。
文書中の例と実際の実装を区別し、必要なら検索対象ディレクトリを限定する。
rgがなければ git grep やIDEの検索・シンボル検索を使う。git grepは通常未追跡ファイルを含まない。
検索の一致なしは機能が不要・仕様がないことの証明にはならない。

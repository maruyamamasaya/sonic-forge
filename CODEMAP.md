# コードと情報の地図

## 現在の入口
| 目的 | 主なファイル | 検索キーワード |
| --- | --- | --- |
| コンセプト・人間向け案内 | README.md | SonicForge、音 |
| 開発の経緯・人向けの入門 | DEVELOPMENT_JOURNEY.md、USER_GUIDE.md | 音素材、楽器、演奏、構成、用語 |
| 音源分離の方針・実機比較 | SOURCE_SEPARATION.md、SEPARATION_BENCHMARK.md、scripts/separation_benchmark.py、benchmarks/separation/、decisions/0045-mlx-separation-backend.md | htdemucs、MLX、worker、分離、run、compare |
| 来歴付き素材ライブラリの仕様・計画 | MATERIAL_LIBRARY.md、decisions/0047-material-library-plan.md | SourceTrack、SeparationRun、MaterialClip、SQLite、元曲frame |
| 全体構想・中長期計画 | ROADMAP.md | 分離、分析、蓄積、スコア、ロードマップ |
| 現在地・次の作業 | CURRENT.md | 未実装、次に行うこと |
| 構成ファイル形式 | ENSEMBLE_FORMAT.md | sfensemble、version、instrument、masterDB |
| 複数楽器の演奏 | ENSEMBLE.md | Ensemble、Play All、パート |
| AI編曲提案 | AI_ARRANGEMENT.md | Arrange、ArrangementProposal、Use Arrangement |
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
| アプリ入口・メイン制作画面 | app/SonicForgeApp.swift、app/WorkspaceView.swift、app/WorkspaceInspector.swift、app/WorkspaceSectionInspector.swift、app/WorkspaceAppearance.swift | WorkspaceView、ensembleWorkspaceActive、Selected clip、setInstrumentSettings | 実アプリ手動確認 |
| 来歴付き素材の保存・復元 | app/MaterialOrigin.swift、app/MaterialStore.swift、app/MaterialLibraryModel.swift、app/MaterialLibraryView.swift、app/MaterialComparison.swift、app/MaterialDeletion.swift | MaterialStore.setTrashed/search/updateAnnotations/comparison、MaterialLibraryModel.showTrash/changeTrashState、MaterialLibraryModel.preview/stopPreview、MaterialStore.prepare/commit/restore/resolve、PlayerModel.openMaterial(clip:)、InstrumentProvenance、SeparationLease | tests/MaterialTests.swift、tests/MaterialSearchTests.swift、tests/MaterialReuseTests.swift、tests/MaterialDeletionTests.swift |
| 曲の分離・試聴・素材採用 | app/SeparationClient.swift、app/SeparationModel.swift、app/SeparationView.swift、scripts/separation_worker.py | SeparationClient.run/validate、SeparationModel.start/cancel/preview、useSeparatedAudio | tests/SeparationTests.swift、実モデルと実UI |
| WAV・デモ・波形解析 | app/AudioAsset.swift | AudioAsset.load、DemoAudio.write、peaks | tests/AudioTests.swift |
| 再生・ファイル選択・状態 | app/PlayerModel.swift | open、load、toggle、stop、seek、playSelection、refreshPlaybackState | tests/AudioTests.swift --playback |
| 選択・ズーム・表示範囲 | app/WaveformEditor.swift | select、setZoom、pan、fitSelection、AudioSelection | tests/AudioTests.swift |
| 選択区間の音声 | app/SelectionAudio.swift | SelectionAudio.write、framePosition、frameCount | tests/AudioTests.swift |
| WAV書き出し | app/WAVExport.swift、app/PlayerModel.swift | WAVExport.write、exportSelection、export、NSSavePanel | tests/AudioTests.swift |
| 構成保存・復元 | app/EnsembleDocument.swift、app/EnsembleModel.swift、app/InstrumentDocument.swift、app/PlayerModel.swift | EnsembleSnapshot、makeArchive/restore、save/load、dirty、restoreLastSession | tests/EnsemblePersistenceTests.swift / --playback |
| 全体WAV書き出し | app/EnsembleExport.swift、app/EnsembleModel.swift、app/EnsembleView.swift | exportWAV、cancelExport、write、Export WAV | tests/EnsembleExportTests.swift |
| 共有楽器の複数クリップ | app/EnsembleClips.swift、app/EnsembleClipEditor.swift、app/EnsembleDuplicateMenu.swift、app/EnsembleModel.swift | additionalClips、allClips、addClip、duplicateClip、editClip、EnsembleClips.events | tests/EnsembleClipTests.swift / 実UI |
| 曲セクション | app/EnsembleSections.swift、app/EnsembleSectionsView.swift、app/EnsembleModel.swift | sections、sectionID、validatePlacement、duplicateSection、addSongDemo | tests/SectionDuplicationTests.swift、tests/EnsembleSectionTests.swift / 実UI |
| 構成タイムライン | app/EnsembleTimeline.swift、app/EnsembleTimelineView.swift、app/EnsembleModel.swift | length、repeatedLength、events、repeatCount、movedStart、movePart、ARRANGEMENT | tests/EnsembleTests.swift / 実UI |
| 複数パート演奏 | app/EnsembleModel.swift、app/EnsembleView.swift、app/SampleInstrument.swift | EnsemblePart.startBeat、EnsembleVoice、timeline、addDemos(staggered:)、destination、Play All | tests/EnsembleTests.swift / --playback |
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

曲全体の履歴: `app/EnsembleModel.swift` のSongState/recordSongEdit/restoreSongEdit、UIはWorkspaceView/EnsembleView、回帰は `tests/WorkspaceTests.swift` のsongHistory。

途中再生/範囲ループ: `app/EnsemblePlayback.swift` のplan、`app/EnsembleModel.swift` のseek/pause/setPlaybackRange、UIはEnsembleTransportControls/EnsembleTimelineView、検証は `tests/EnsemblePlaybackTests.swift`。

パートのパン: EnsemblePart.pan / SampleInstrument.pan / EnsemblePartSnapshot.pan、EnsemblePanControl（WorkspaceInspector/EnsembleView）、addDemos(panned:)。検証は `tests/EnsemblePanTests.swift`、保存形式は `ENSEMBLE_FORMAT.md`。

実音源の楽器化評価: `scripts/real_audio_evaluation.py` → `scripts/real_audio_evaluation.swift` → 本番MaterialStore/InstrumentDocument/EnsembleExport。結果と評価の限界は[実音源評価](REAL_AUDIO_EVALUATION.md)。音声/DB/詳細測定は無視対象のbuild配下へ出力する。

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

メイン選択編集のモデル検証は tests/WorkspaceTests.swift。UIはWorkspaceView/Inspector、旧一覧はEnsembleView、素材編集はStudioView。

音符プレビューは app/PerformanceNoteLayout.swift の PerformanceNoteLayout.make と app/PerformanceNoteView.swift の PerformanceNoteView。検証は tests/WorkspaceTests.swift と実UI。

自然木素材は app/Resources/Textures/、bundleへのコピーは scripts/build.sh。

下段音符編集: app/ClipNoteEditor.swift の SelectedClipNotes / ClipNoteGrid → app/EnsembleModel.swift の editClipNotes。検証は tests/WorkspaceTests.swift。

音符履歴入口: EnsembleModel.canUndoNotes / canRedoNotes / restoreNoteEdit。UIはClipNoteEditor.swiftのUndo/Redo、検証はtests/WorkspaceTests.swift。

複数音符: ClipNoteEditor.swift の pick/group/offsetAction、ClipNoteGridの矩形選択 → EnsembleModel.editNoteGroup → editClipNotes。テストはWorkspaceTests.swift。

クオンタイズ入口: PerformanceDocument.swift の NoteQuantizeGrid、EnsembleModel.editNoteGroup(.quantize)、ClipNoteEditorのNote quantize grid / Quantize selected clip notes。tests/WorkspaceTests.swift。

選択音符の強弱: ClipNoteEditorのSelected notes velocity mode/value / Apply velocity to selected notes → EnsembleModel.editNoteGroup(.velocity/.velocityOffset)。tests/WorkspaceTests.swift。

選択音符の長さ: ClipNoteEditorのSelected notes length mode/value / Apply length to selected notes → EnsembleModel.editNoteGroup(.duration/.durationScale)。tests/WorkspaceTests.swift。

音符クリップボード: EnsembleModel.copiedNotes / copyClipNotes / pasteClipNotes → editClipNotes。UIはClipNoteEditorのCopy selected clip notes / Note paste beat / Paste copied clip notes、検証はWorkspaceTests.swift。

編曲提案: app/ArrangementGeneration.swift / ArrangementComposer.swift / ArrangementComposerView.swift → EnsembleModel.arrangementBrief / applyArrangement。検証はtests/ArrangementGenerationTests.swift。共有通信はCodexPerformanceClient.generateJSON / OpenAIPerformanceClient.jsonRequest / generateJSON。

日本語表示・用語ヘルプ: app/JapaneseUI.swift の JapaneseUI / StudioHelpTopic / StudioHelpButton（help.guide / help.search）。入口はWorkspaceView / StudioView、短い説明は各設定のhelp属性。AI用ラベルと識別子はAI_OPERATIONS.mdの日本語UIとヘルプ。

パートEQ: app/PartEQ.swift のPartEQ/apply/makeNode、EnsemblePart.eq、EnsembleVoice.setEQ、EnsembleEQControl（WorkspaceInspector/EnsembleView）、addDemos(equalized:)。検証はtests/EnsembleEQTests.swift、形式はENSEMBLE_FORMAT.md。

パートリバーブ: app/PartReverb.swift（isValid/tailSeconds/makeNode）、EnsemblePart.reverb、EnsembleVoice.setReverb、EnsembleReverbControl（WorkspaceInspector/EnsembleView）、addDemos(reverberant:)。余韻はEnsembleModel.play/EnsembleExport.write、検証はtests/EnsembleReverbTests.swift。

パートディレイ: app/PartDelay.swift（isValid/tailSeconds/apply）、EnsemblePart.delay、EnsembleVoice.setDelay、EnsembleDelayControl（WorkspaceInspector/EnsembleView）、addDemos(delayed:)。余韻はEnsembleModel.play/EnsembleExport.write、検証はtests/EnsembleDelayTests.swift。

パートコンプレッサー: app/PartCompressor.swift（isValid/apply/makeNode）、EnsemblePart.compressor、EnsembleVoice.setCompressor、EnsembleCompressorControl（WorkspaceInspector/EnsembleView）、addDemos(compressed:)。検証はtests/EnsembleCompressorTests.swift、保存形式はENSEMBLE_FORMAT.md。

マスターリミッター: app/MasterLimiter.swift（MasterLimiter/EnsembleMasterBus）、EnsembleModel.limiter/updateGains/play、EnsembleExport.write、app/MasterLimiterControl.swift（下段/全パート）、addDemos(limited:)。検証はtests/MasterLimiterTests.swift、操作はMASTER_LIMITER.md。

完全削除/容量回収: [MATERIAL_DELETION.md](MATERIAL_DELETION.md)、MaterialStore.prepareDeletion/deletePermanently/retain/pendingReclaims、MaterialAudioLease、MaterialLibraryModel.reviewDeletion/confirmDeletion、MaterialDeletionReview。検証はtests/MaterialDeletionTests.swift。

素材参照・保護解除: app/MaterialDeletion.swift（protectionReview/prepareRelease/releaseProtection）、app/MaterialLibraryModel.swift（reviewProtections/reviewRelease/confirmRelease）、app/MaterialLibraryView.swift（参照シート）。

素材の一括完全削除: app/MaterialDeletion.swift（prepareBatchDeletion/集合単位のdeletionPlan/deletePermanently）、app/MaterialLibraryModel.swift（deletionSelection/reviewBatchDeletion）、app/MaterialLibraryView.swift（ゴミ箱のチェック/対象一覧/共通確認）。

低音の基準音: NotePitch.rootRange/keyboardRange/computerBase、PlayerModel.computerNote、MIDIInput.resetPerformance、InstrumentKeyboard/WorkspaceInspector。保存はInstrumentDocument/EnsembleDocument、検証はtests/RootRangeTests.swift（--roots-only / --playback）。[仕様](ROOT_NOTE_RANGE.md)。

音高推定: app/PitchEstimation.swift（PitchEstimator/PitchAnalysis）、app/PitchEstimateControl.swift（Studio/Inspector共通）。tests/PitchEstimationTests.swift / --pitch-only、実音源はscripts/evaluate_pitch.sh → scripts/pitch_evaluation.swift。[仕様](PITCH_ESTIMATION.md)。

音程評価デモ: app/PitchCorpus.swift / app/PitchDemoMenu.swift、PlayerModel.loadPitchDemo。データはapp/Resources/PitchCorpus、検証はtests/PitchCorpusTests.swift、再作成scripts/prepare_pitch_corpus.py、評価scripts/evaluate_pitch_corpus.sh → scripts/pitch_corpus_evaluation.swift。[評価記録](PITCH_EVALUATION.md)。

公開楽譜の制作例: scripts/create_score_demo.py（Satieの固定版MIDI/声部分配）→ scripts/score_demo.swift（音源コピーの準備・既存保存/レンダーAPI）。[仕様と出典](SCORE_DEMO.md)。

MIDIファイル: app/MIDIFileImport.swift、app/MIDIFileImportView.swift、WorkspaceViewのmidi.import.open、EnsembleModel.importMIDI。tests/MIDIFileImportTests.swift / --midi-file-only、公開fixture tests/Fixtures。私有素材の限定分析はscripts/prepare_midi_materials.py → midi_material_scan.swift → midi_material_demo.swift。[仕様](MIDI_IMPORT.md)。

ボイス単体の音作り比較: `scripts/voice_sound_study.swift`。既存ローカルvoice/input.wavから3条件の楽器/構成/WAVを新規buildへ生成。[比較記録](sessions/2026-10-20-voice-sound-study.md)。

声の長音化/母音旋律: scripts/voice_vowel_song.py、別話者の日本語仮歌: scripts/japanese_nursery_study.py、信号検証: scripts/test_voice_vowel_song.py。[処理](VOICE_SOUND_DESIGN.md)。

ローカル母音モデル試作: scripts/local_vowel_model_study.py。[モデル/入口/限界](LOCAL_VOWEL_MODEL.md)。取得済みローカルモデルと参照音声だけで実行し、私有音声やモデルはbuild内。

5母音の比較編集: scripts/prepare_five_vowel_comparison.py。生成はlocal_vowel_model_study.pyの--five-vowels。前回UのPCM一致/先頭発声切出し/RMS合わせ/試聴列を扱う。[仕様](LOCAL_VOWEL_MODEL.md)。

長音の短長比較: scripts/prepare_sustained_vowel_comparison.py。元の5母音WAVを保持し、同じ3秒参照で生成した長音の先頭発声をRMS合わせで並べる。[結果](LOCAL_VOWEL_MODEL.md)。

母音和音の単体比較: scripts/vowel_chord_study.py。既存長音へローカルRubber Bandのフォルマント保持移調を使い、3音の長三和音と単音比較を生成。[処理/結果](LOCAL_VOWEL_MODEL.md)。

母音コード進行の響き比較: scripts/vowel_progression_study.py。長音からI–vi–IV–Vと短いルーム残響の有無を生成。[仕様](LOCAL_VOWEL_MODEL.md)。

母音の小曲: scripts/vowel_miniature_study.py。童謡/固定版ジムノペディの短い抜粋を、うの旋律と薄いあの伴奏へ編曲。[仕様](LOCAL_VOWEL_MODEL.md)。

母音のフレーズ表情: scripts/vowel_expressive_gymnopedie.py。ジムノペディ16小節へ音量の山/息継ぎ/緩いテンポ変化を付け、均一版と比較。[仕様](LOCAL_VOWEL_MODEL.md)。

母音レガート比較: scripts/vowel_legato_study.py。表情版reportから旋律を接続し、前回コーラスを保持して新旧比較。[仕様](LOCAL_VOWEL_MODEL.md)。

母音ビブラート比較: scripts/vowel_vibrato_study.py。レガート旋律へ遅れて入る微小変調、既知リバーブの復元、コーラス不変の新旧比較。[仕様](LOCAL_VOWEL_MODEL.md)。

母音のフレーズ切替: vowel_legato_study.pyの--phrase-vowels → vowel_vibrato_study.py → scripts/prepare_vowel_phrase_comparison.py。既存ビブラート版との同区間/RMS比較。[仕様](LOCAL_VOWEL_MODEL.md)。

母音切替の連続化: scripts/vowel_transition_study.py。共通位相の旋律へaの包絡を徐々に移し、母音切替版との比較を出力。[仕様](LOCAL_VOWEL_MODEL.md)。

母音の息づかい/語尾: scripts/vowel_breath_study.py。連続化版のフレーズ前後へ小さな合成息成分と語尾減衰を加え、前回比較。[仕様](LOCAL_VOWEL_MODEL.md)。

日本語歌詞/声区の試作: local_vowel_model_study.py --lyric-study → scripts/japanese_lyric_gymnopedie.py。ローカル参照条件付き音声を動的移調/時間配置し、地声/裏声風の音色と母音版比較を出力。[仕様と制限](LOCAL_VOWEL_MODEL.md)。

歌詞の拍感改善: japanese_lyric_gymnopedie.pyの--mora-grid / --previous-lyrics。近似モーラ境界/拍配置と追加音程補正。[仕様と限界](LOCAL_VOWEL_MODEL.md)。

短い歌詞のリズム: japanese_lyric_gymnopedie.pyの--rhythmic-words / --vowel-fill。半拍単語群、発音窓、推定頭の輪郭強調、母音補完と前回比較。[仕様](LOCAL_VOWEL_MODEL.md)。

歌詞の接続診断: scripts/lyric_connection_recovery.py。完全な元発話/原尺を保つ朗読寄り比較。自然な歌唱としては未達。[品質不良と診断](LOCAL_VOWEL_MODEL.md)。

声の用途/歌唱中止の判断: [VOICE_STUDY_SUMMARY.md](VOICE_STUDY_SUMMARY.md)。

ナレーション完成版: [設定と再生成](NARRATION.md)。原稿はscripts/spoken_low_laugh_text.json。生成はspoken_character_study.py（--low-register-anchor）、加工はprepare_spoken_character_demo.py→narration_natural_highs.pyのsoft-highs→spoken_breath_endings.py。追加のsource prosodyは使用しない。[圧縮履歴](NARRATION_HISTORY.md)。

楽器サンプルの仕上げ: app/SamplePreparation.swift（SamplePreparationProcessor.process）→app/SamplePreparationModel.swift（render/prepare/preview/cancel）→app/SamplePreparationView.swift。InstrumentKeyboard入口、PlayerModel.applyPreparedSample/undoSamplePreparationで採用。tests/SamplePreparationTests.swift、--sample-preparation-only。[仕様](SAMPLE_PREPARATION.md)。

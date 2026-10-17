# SonicForge

音を鍛造し、新しい楽器や音楽を生み出す。

GitHub: [maruyamamasaya/sonic-forge](https://github.com/maruyamamasaya/sonic-forge)

macOS向けのSample Studio。WAVを読み込み、波形を見ながら再生・一時停止・停止・シーク・音量調整ができます。
波形のズーム、ドラッグによる範囲選択、選択部分だけの再生とWAV書き出しにも対応しています。
音源がなくても、起動時に読み込まれる合成デモを再生・画面鍵盤で演奏できます。
Rootで基準音を設定し、Use Selectionで選択した部分をサンプラー楽器として演奏できます。
鍵盤上のADSRで立ち上がりと余韻を調整できます。
Save…で音源・基準音・ADSR・ループ設定をまとめて保存し、Open…で復元できます。次回起動時には最後の保存済み楽器を復元します。

## 起動
macOS 14以上とXcodeの開発ツールが必要です。

```sh
sh scripts/build.sh
open build/SonicForge.app
```

Play／Spaceで再生、Open WAV…／⌘Oで音源を読み込み、Load Demoでデモに戻ります。
範囲をドラッグしてPlay Selection（Shift-Space）で試聴できます。＋／−でズーム、Fit Allで全体に戻ります。
Export WAV…で選択範囲を32-bit Float WAVとして保存できます。
対応形式と詳しい操作は [運用ガイド](OPERATIONS.md)、検証は [TESTING.md](TESTING.md)。

## 開発ガイド
- [現在地と次の作業](CURRENT.md)
- [現在の構成](ARCHITECTURE.md)
- [コードの場所と検索方法](CODEMAP.md)
- [検証方法](TESTING.md)
- [開発・運用手順](OPERATIONS.md)
- [AIエージェントの作業ルール](AGENTS.md)
- [設計判断](decisions/README.md)
- [作業履歴](sessions/README.md)

サンプルは範囲指定ループとクロスフェードに対応。操作は[運用ガイド](OPERATIONS.md#サンプルループ)を参照。

最大8音の和音演奏に対応。画面鍵盤のHold keys、PC鍵盤、Demo chordで試せます。詳しくは[演奏操作](OPERATIONS.md#和音の演奏)を参照。

MIDI INで外部キーボードを選択できます。実機なしの確認はTest input → MIDI chord。[MIDI操作](OPERATIONS.md#外部midiキーボード)を参照。

弾けなくてもプリセットを選んでAuto playで試聴できます。MIDIの強弱・サステインペダルにも対応。[自動演奏と操作](OPERATIONS.md#弾かずに試す自動演奏)を参照。

AIによる操作・自動演奏の引き継ぎは[AI操作ガイド](AI_OPERATIONS.md)を参照。

自動演奏はEdit…でテンポ・移調・強弱と音符を編集し、演奏専用ファイルへ保存できます。[演奏データ形式](PERFORMANCE_FORMAT.md)はAI生成にも使う共通形式です。

保存した楽器の検索・試聴・読み込みはLibrary…から。音源がなくてもAdd Demosで試せます。詳しくは[操作ガイド](OPERATIONS.md#楽器ライブラリ)を参照。

Compose…から言葉で演奏候補を作れます。Codex CLI・OpenAI API・他のAIのJSON貼り付けに対応。接続不要のDemoもあります。[AI生成ガイド](AI_GENERATION.md)を参照。

Ensemble…で最大4つの楽器と演奏を組み合わせられます。Add Demo Duoから同時演奏を試せます。[複数パートの操作](ENSEMBLE.md)を参照。

EnsembleのSave…で全パートの音源・演奏・ミックスをまとめて保存し、再起動後も復元できます。[構成の保存](ENSEMBLE.md#構成を保存復元する)を参照。

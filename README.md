# SonicForge

音を鍛造し、新しい楽器や音楽を生み出す。

GitHub: [maruyamamasaya/sonic-forge](https://github.com/maruyamamasaya/sonic-forge)

macOS向けのSample Studio。WAVを読み込み、波形を見ながら再生・一時停止・停止・シーク・音量調整ができます。
波形のズーム、ドラッグによる範囲選択、選択部分だけの再生とWAV書き出しにも対応しています。
音源がなくても、起動時に読み込まれる合成デモを再生できます。

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

# 演奏データ形式 v1

正本: [PerformanceDocument.swift](app/PerformanceDocument.swift)。AIが生成する場合も、コードではなくこの形式のデータを渡す。
操作は[AI操作ガイド](AI_OPERATIONS.md)、人向け手順は[OPERATIONS.md](OPERATIONS.md)。アプリ内生成は[AI生成](AI_GENERATION.md)を参照。

## ファイルと例
UTF-8 JSON、拡張子.sfperformance、最大1 MB。音源は含まない。現在の楽器で再生する。
全フィールド必須。チャンネルはファイル内0〜15、編集画面では1〜16。

```json
{
  "version": 1,
  "name": "Gentle pedal",
  "tempo": 120,
  "transpose": 0,
  "velocityPercent": 100,
  "notes": [
    {"beat": 0, "duration": 0.5, "pitch": 60, "velocity": 64, "channel": 0}
  ],
  "pedals": [
    {"beat": 0, "down": true, "channel": 0},
    {"beat": 2, "down": false, "channel": 0}
  ]
}
```

この例ではC4を0.25秒押し、ペダルで1秒まで保持する。ループOFFではサンプル末尾が先に来る場合がある。

## 値と制限
| フィールド | 意味・範囲 |
| --- | --- |
| version | 整数1。未知版は拒否 |
| name | 全体で1〜80文字。空白のみは不可 |
| tempo | 40〜240 BPM。有限数 |
| transpose | 整数−24〜24半音。元のpitchは変更せず再生時に加算 |
| velocityPercent | 25〜150%。有限数。各音のvelocityへ乗算・四捨五入し1〜127に収める |
| notes | 1〜256音符 |
| notes[].beat | 四分音符を1とした開始位置。有限数、0以上 |
| notes[].duration | 四分音符を1とした長さ。有限数、0より大きい。beat+durationは256以下 |
| notes[].pitch | 整数MIDI 0〜127。移調後も0〜127 |
| notes[].velocity | 整数1〜127。0は保存用音符として拒否 |
| notes[].channel | 整数0〜15 |
| pedals | 0〜64件。使用しない場合も空配列を指定 |
| pedals[].beat | 四分音符を1とした位置、有限数0〜256 |
| pedals[].down | 真偽値。true=踏む、false=戻す |
| pedals[].channel | 整数0〜15 |

同じチャンネル・音程の押鍵区間の重複は拒否する。離鍵後にペダル保持された同音の再押鍵は可能。
ペダル保持を含め、同時に保持する異なる音程は8音以内。Releaseの余韻による一時的超過はエンジンの既存ボイス置き換え規則に従う。
最後に全チャンネルのペダルが戻っている必要がある。Note Offはdurationから生成するためファイルへ別途記述しない。

## 変換と検証の順序
1. 読み込み前にサイズを確認しJSONをデコードする。形式・件数・有限数・値の範囲を検証する。
2. pitchへtranspose、velocityへvelocityPercentを適用し、Note On/OffとCC64へ変換する。
3. beat順に並べる。同時刻はペダル解除→離鍵→ペダルON→押鍵。同順位は配列由来の順序を維持する。
4. 押鍵の重複・保持音数・最後のペダル解除を検証し、time=beat×60/tempoで秒へ変換する。
5. 再生直前に現在の楽器の基準音±24半音も検証する。1音でも範囲外なら演奏全体を開始しない。

読込時と保存時は形式の検証を行い、保存はatomic write。不正データの読込は現在の編集内容を置き換えず、不正データの保存は既存ファイルを変更しない。
再生データは開始時にスナップショット化し、仮想CoreMIDI経由で既存の和音・ADSR・ループへ渡す。再生中はUI編集を無効化する。

## AIとの接続点
Compose…のCodex CLI / OpenAI API / Other AIはこの形式を生成・検証する。生成候補は通常の形式制限に加え4小節（16拍）・64音符まで。strict JSON SchemaはPerformanceGeneration.schemaから作るが、重複・音域・同時保持数の正本は引き続きPerformanceDocument.events。
外部AIはEdit… → Open…で既存ファイルを読み込むことも可能。この通常読み込みは既存形式の最大256拍・256音符を維持する。外部操作API・MCPは未実装。Swiftのコード生成・実行や任意生MIDIの実行は要求しない。
既存音色の.sfinstrument v4とは別ファイル。音色・演奏の自動ひも付けや最後の演奏の起動時復元は行わない。接続と候補採用手順は[AI_GENERATION.md](AI_GENERATION.md)。

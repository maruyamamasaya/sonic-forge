# 公開楽譜から作った試作音源

2026-10-20。今あるサンプラー・複数パート・構成保存・WAV出力を使って、聴ける曲と再編集用データを作る試作。

## 選んだ楽譜

Erik Satie「Gymnopédie No. 1（ジムノペディ第1番）」、1888年。Mutopia Project / Evin RobertsonによるDover版に基づく入力データを使う。公式配布ページの表記はPublic Domain。

- [楽譜・利用条件・MIDIの入口](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=37)
- [MIDI](https://www.mutopiaproject.org/ftp/SatieE/gymnopedie_1/gymnopedie_1.mid)
- [楽譜PDF](https://www.mutopiaproject.org/ftp/SatieE/gymnopedie_1/gymnopedie_1-a4.pdf)
- [LilyPondソース](https://www.mutopiaproject.org/ftp/SatieE/gymnopedie_1/gymnopedie_1.ly)

MIDIのSHA-256を生成スクリプトに固定し、異なる版は拒否する。特定の楽譜に合わせた変換であり、任意のMIDI/譜面をアプリが直接読み込めるという意味ではない。

## 作った編成と変更

最初の繰り返しに入る前の第1終止まで、39小節・117四分音符拍を使用。テンポ72 BPM。曲全体/原曲の忠実な演奏再現ではなく、途中までの試作アレンジである。

1. Piano: 旋律・和音・低音をピアノで演奏する3パート。
2. Woodland: 旋律をギター、和音をピアノ、低音を弓のコントラバスにした3パート。旋律パートには終止部分の原譜の和音も含む。

音源は[評価用録音](PITCH_EVALUATION.md)と同じIowa MIS原録音/同梱切片。権利と出典は[NOTICE](app/Resources/PitchCorpus/NOTICE.md)。元音源を変更せず、試作用コピーをモノラル化してピーク−1 dBFSへ調整。名目音と一致する推定値のセント差に基づき、ごく小さくリサンプリングして調律する。これは制作スクリプト内の前処理であり、アプリに自動調律機能を追加したものではない。実際の補正量と原本ハッシュは出力のrender-report.jsonへ残す。

ピアノは原録音から8秒、ギターは8秒、ベースは既存1.2秒を使用。ギターと弓のベースには60 msクロスフェードのループ、各パートに少量のリバーブ/パンとコンプレッサーの補正音量+24 dB、マスターに既存リミッターを設定する。

MIDIの右手/左手を、この版だけの規則で旋律/和音/低音へ分ける。9〜12小節のF♯4タイはLilyPond譜と照合して12拍へ戻す。MIDIにある重複した2件の離鍵イベントは無視し、原譜にない音符は追加しない。相対強弱を残しながら和音/低音を抑え、サステインペダルは省略した。サンプルの移調では再生速度/音の長さも変わり、楽器の本物らしさや聴感の品質は別途試聴が必要。

## 再作成と開き方

```sh
# Iowa原録音がない場合は明示的に取得
/usr/bin/python3 scripts/prepare_pitch_corpus.py --download
# 新しいbuild/配下へ作成（既存フォルダを上書きしない）
python3 scripts/create_score_demo.py build/my-gymnopedie-demo
```

MP3は任意の試聴用コピー。ffmpegがある環境では、生成後に次のように作れる（WAVへ音量変更を加えない）。

```sh
ffmpeg -n -i build/my-gymnopedie-demo/Gymnopedie-Piano.wav -codec:a libmp3lame -b:a 192k build/my-gymnopedie-demo/Gymnopedie-Piano.mp3
ffmpeg -n -i build/my-gymnopedie-demo/Gymnopedie-Woodland.wav -codec:a libmp3lame -b:a 192k build/my-gymnopedie-demo/Gymnopedie-Woodland.mp3
```

初回だけMutopia MIDIをbuild/score-sourceへ取得する。以降はハッシュ検証付きで再利用する。Swift生成プログラムは通常テストが使う本体ソース一式をコンパイルし、InstrumentDocument/PerformanceDocument/EnsembleDocument/EnsembleExportを使う。普段の素材DBや登録楽器をスクリプトから編集しない。

出力:

- `Gymnopedie-Piano.wav` / `Gymnopedie-Woodland.wav`: 48 kHzステレオFloat32。
- 同名`.mp3`: WAVから音量を変えずに192 kbpsで圧縮した試聴用コピー（生成後にffmpegで作成）。
- 同名`.sfensemble`: 音声同梱でSonicForgeから開いて再編集できる構成。
- `.sfperformance`: 旋律/和音/低音の演奏データ。
- `.sfinstrument`: 各音源の基準音/ADSR/ループを含む楽器。
- `source.json` / `render-report.json`: 楽譜の出典・変更・入力不変・WAV測定結果。

構成画面の「構成を開く」から.sfensembleを選択し、3パート・4区切り・テンポ72を確認する。クリップは曲頭からの配置で、区切り帯は見渡すためのもの。再生/全停止、音符編集、楽器差し替え、別名保存が可能。元の曲を残す場合は先に保存する。

## 今回の確認

生成・保存復元・WAV再読み込み・非無音/有限値/ピーク・実画面の確認結果は[作業記録](sessions/2026-10-20-score-demo.md)へ残す。音声と生成物はbuild/に置き、Gitへは変換スクリプトと出典/作業記録だけを残す。

今回の完成版は`build/gymnopedie-demo-2026-10-20-final/`。両版101.2秒、ピークはPiano −6.30 dBFS、Woodland −5.67 dBFS。初回の音量が小さかったため、素材コピーのピークと既存コンプレッサーの補正量を調整した。WAV/MP3の後段の音量正規化はしていない。

後続で[アプリ内MIDI読込](MIDI_IMPORT.md)を実装した。このページの固定変換と異なり、SMFの離鍵をそのまま読む。

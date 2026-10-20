# ナレーション完成版の設定

2026-10-20、ユーザー指定で高域を軽く抑えた版を完成版に採用。低めの早口を軸に、笑い混じり・言い淀み・途中の感情変化を含むローカル音作り。アプリ未組込。試行錯誤は[圧縮した判断履歴](NARRATION_HISTORY.md)へまとめ、通常はこの文書だけを参照する。

## 完成音源と必要な素材

ローカル保存先は`sample_music/narration-final-2026-10-20/`（Git対象外）。

| ファイル | 用途 |
| --- | --- |
| expressive-breath-ending-demo.wav | 完成版・14場面/約2分43秒/24 kHzモノラルFloat32 |
| 01-low-fast-laugh-highlights.wav | 早口・笑い・感情転換の約42秒抜粋 |
| transcript.md / prompts.json | 時刻付き台本 / 採用した生成原稿 |
| references/subdued-2.wav | 好評の早口と同じ元音源3.2秒参照・全場面で固定 |
| references/liked-register-anchor.wav | 好評の早口の生生成・高音を避ける目安 |
| references/baseline.wav / 未使用の5参照 | 既存生成スクリプトが検査する互換入力。採用原稿はsubdued-2のみ使用 |
| generation-report.json / high-band-report.json / report.json / manifest.json | 生成候補/高域軽減/語尾の加工条件/保存ファイルhash |

語尾処理前の対照と同じ台詞の比較も保存済み。モデルとvenvは既存のbuild/local-vowel-model内を使い、完成版フォルダには複製しない。元音声・台本・原稿・参照・モデルはローカルで扱う。

## 固定する設定

| 項目 | 採用値 |
| --- | --- |
| モデル | mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit |
| revision | 37e955a1deb861c088ae5f3a67043185f3d1a60c |
| 配置 | build/local-vowel-model/model-1.7b-base |
| 実行環境 | build/local-vowel-model/venv/bin/python（Python 3.11、mlx-audio 0.6.0、MLX 0.32.4、NumPy/SciPy、Rubber Band 4.0.0） |
| 声の参照 | 従来3.2秒のsubdued-2、speaker embedding、ref_text=None、Japanese |
| 生成 | seed 7、temperature 0.7、top_k 50、top_p 0.95、repetition_penalty 1.1、上限256 tokens |
| 高音を避ける選択 | 好評の基準より中央値またはp90が2半音超ならseed 19でもう1回生成。完結した候補から高域超過の少ないものを選択 |
| 原稿 | scripts/spoken_low_laugh_text.json。referenceは全てsubdued-2、pitch_wander_semitones=0、air_mix=0 |
| 高域の処理 | narration_natural_highs.pyのsoft-highs。3.8 kHz以上を最大2.5 dB動的に抑え、息/語尾の工程へ渡す |
| 追加の元参照特徴加工 | spoken_source_prosody.pyは適用しない。追加の微小ピッチ/強弱/高域加工を重ねない |

笑い/間/感情は文章全体と句読点で誘導する。「ふふ」「ふう」「はあ」、少しの言い直しや途中の気持ちの変化を原稿に含める。categoryは管理用ラベルで、演技instructではない。低めを基本に、大声の驚嘆や高く張る方向を避ける。全体をピッチダウンしない。音高の選択は近似で、笑いや声質一致の保証ではない。

## 再生成する手順

プロジェクトルートから、既存環境/モデルと上記ローカル素材を使う。次のrunフォルダは未使用の名前へ変更する。出力は上書きしない。

```sh
build/local-vowel-model/venv/bin/python scripts/spoken_character_study.py \
  --model build/local-vowel-model/model-1.7b-base \
  --references sample_music/narration-final-2026-10-20/references \
  --baseline-reference sample_music/narration-final-2026-10-20/references/baseline.wav \
  --low-register-anchor sample_music/narration-final-2026-10-20/references/liked-register-anchor.wav \
  --prompts scripts/spoken_low_laugh_text.json \
  --output build/narration-final-rerun/raw
build/local-vowel-model/venv/bin/python scripts/prepare_spoken_character_demo.py \
  --input build/narration-final-rerun/raw \
  --output build/narration-final-rerun/pace \
  --max-reel-seconds 180
build/local-vowel-model/venv/bin/python scripts/narration_natural_highs.py \
  --pace build/narration-final-rerun/pace \
  --references sample_music/narration-final-2026-10-20/references \
  --output build/narration-final-rerun/natural
build/local-vowel-model/venv/bin/python scripts/spoken_breath_endings.py \
  --input build/narration-final-rerun/natural/soft-highs \
  --references sample_music/narration-final-2026-10-20/references \
  --output build/narration-final-rerun/final
```

natural/soft-highsが採用経路。natural/pace-onlyは比較用で完成版には使わない。これは完成した14場面を再現する手順。別原稿はJSONをコピーしてtext/category/paceを編集し、参照と他の設定は維持する。paceはnormal/quick/accelerate/settle。既存の連結工程には100秒超〜指定上限未満の検査があり、任意長の短文生成UIではない。180秒の指定は検査上限だけで、尺を強制変更しない。モデル推論はローカルMetalを使用し、通信をコードで遮断する。

## 維持する音作り

1. 速度: quickは1.16倍、accelerateは1→1.2倍、settleは1.14→0.98倍。全発話の時間mapで、言葉を切り貼りしない。
2. 高域のかさつき: 元参照の高域比率を目安に、3.8 kHz以上の成分だけを最大2.5 dB動的に抑える。20 ms平滑化で変化を穏やかにする。低い声の芯と生成された息を残し、追加の抑揚/強弱/高域加工は重ねない。
3. 息/語尾: 元参照の包絡から間を240〜480 msに収め、末尾の有音160 msを最大約1.72 dBだけ弱める。後ろの空気成分は100 msで元のゲインへ戻す。末尾の音や無音は削らない。新しい合成息ノイズを加えない。

呼吸と子音の分離や音素の正確な整列はしていない。間/減衰の候補がなければ弱い既定値を使う。これらはモデルの再学習ではなく、元参照を参考にした控えめな後加工。

## 完了確認と停止

生成reportのall_natural_eos/all_references_unchanged=true、blocked_network_attempts=0を確認。候補seed/音域と加工reportを残し、WAVの再読込・有限/非無音/非クリップ・元参照hash・連結/間を検査する。声の近さ/笑い/自然さは試聴で判断する。今回の採用版はユーザー指定で完成扱いとするが、任意の新原稿まで品質を保証しない。

停止は実行中CLIをCtrl-C。report未完成の出力は途中結果。既存検証は[TESTING.md](TESTING.md)を参照。アプリへの組込や歌唱の再開は今回の範囲に含めない。

# 母音コーラスのコード進行とリバーブ比較
Date: 2026-10-20

## Request
好評だった「あー/うー」の和音で短い進行を作り、軽いリバーブの有無を比較。音作りのみ。
## Investigation
CURRENT/CODEMAP/AI_OPERATIONS/TESTINGと既存和音スクリプト、長音を確認。既存Rubber Bandのフォルマント保持移調を再利用。
## Changes
scripts/vowel_progression_study.pyを追加。I–vi–IV–V、1.1秒間隔、各6秒。各母音のドライ/簡易ルーム残響版/比較と全体比較をbuildへ出力。原音の長さを保ち、同じ発声を再利用。新しいAI生成/モデル取得/外部送信/アプリ変更なし。処理詳細は[正本](../LOCAL_VOWEL_MODEL.md)。
## Validation
入力hash不変、有限/非無音/非クリップ、WAV再読込PCM一致、ペアRMS差0.001 dB以内、残響末尾収束に成功。独立再計算で畳み込み結果の差1e-7未満と試聴列の完全一致を確認。FastとFull文書検査、git diff --check成功。native Fullは今回未実行（アプリソース変更なし、独立DSP試作のみ）。聴感はユーザー確認待ち。
## Result
build/local-vowel-model/vowel-progression-studyに4条件と比較音源。アプリ未組込、未コミット。
## Remaining Issues
絶対音高は未調律。元の声の音程変動は残る。自然な合唱や知覚音量の完全一致を保証しない。

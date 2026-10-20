# NarrationStudioへ切り出し

ユーザー作成の空MyVoiceを指定のNarrationStudioへ改名し、採用済みナレーションの必要なDSP/生成/参照/完成音源/設定をコピー。SonicForgeモジュールのimportを除き、固定14場面/100秒以上の制約を外したCLIを用意。モデル/venvは設定で既存配置を共有。元ファイルは保持。移し先はローカルGit初期化のみ、UI/コミット/公開なし。

検証: 移植したDSPの数値一致、5単体テスト/移し先Full、一文6.8秒の生成・全EOS/参照不変/通信0/WAV PCM/hash/Git除外。SonicForgeは文書のみ更新しFast/Full文書/diff確認、nativeは既記録の環境制約で未再実行。歌唱再開/アプリ組込なし。[採用元設定](../NARRATION.md)。

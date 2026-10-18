import SwiftUI

/// Presentation only: persisted names, enum raw values and file formats are not translated.
enum JapaneseUI {
    static func preset(_ preset: MIDIPerformancePreset) -> String {
        switch preset { case .softChords: return "柔らかい和音"; case .arpeggio: return "分散和音"; case .pedalStudy: return "ペダルの演奏" }
    }
    static func provider(_ value: String) -> String {
        switch value { case "Demo": return "デモ（AIなし）"; case "Other AI": return "他のAI（JSON貼り付け）"; default: return value }
    }
    static func wood(_ value: String) -> String {
        switch value { case "walnut": return "ウォルナット"; case "oak": return "ホワイトオーク"; default: return "チェリー" }
    }
    static func status(_ value: String) -> String {
        for (english, japanese) in [("Instrument saved · ", "楽器を保存済み・"), ("Instrument opened · ", "楽器を読み込み済み・"),
            ("Saved · ", "保存済み・"), ("Opened · ", "読み込み済み・"),
            ("Restored · ", "復元済み・"), ("Exported · ", "書き出し済み・")] where value.hasPrefix(english) {
            return japanese + String(value.dropFirst(english.count))
        }
        if value == "Export cancelled" { return "書き出しを中止しました" }
        return value
    }
    static func preview(_ value: String) -> String {
        if value.hasSuffix(" · Loop") { return String(value.dropLast(7)) + "・ループ" }
        if value.hasSuffix(" · One-shot") { return String(value.dropLast(11)) + "・一度だけ再生" }
        return value
    }
    static func envelopeName(_ value: String) -> String {
        switch value { case "Attack": return "立ち上がり"; case "Decay": return "減衰時間"; case "Sustain": return "保持音量"; default: return "余韻時間" }
    }
    static func envelopeHelp(_ value: String) -> String {
        switch value {
        case "Attack": return "発音してから最大音量まで立ち上がる時間です。"
        case "Decay": return "最大音量から、押している間の保持音量へ下がる時間です。"
        case "Sustain": return "鍵盤を押している間の音量です。時間ではありません。"
        default: return "鍵盤を離してから音が消えるまでの時間です。"
        }
    }
    static func fieldHelp(_ value: String) -> String {
        switch value {
        case "音程": return "MIDI番号で指定します。60はC4。音が高いほど数値が大きくなります。"
        case "開始", "貼付位置": return "クリップ先頭を0とした拍数です。1拍は四分音符1個分です。"
        case "長さ": return "音符を押している長さを拍数で指定します。離鍵後の余韻は別です。"
        case "強弱": return "音符ごとの強さを1〜127で指定します。大きいほど強く鳴ります。"
        case "移動拍": return "選んだ音符をまとめて動かす拍数。負の値は前へ移動します。"
        case "移動音程": return "選んだ音符をまとめて上下させる半音数。12で1オクターブ上です。"
        default: return "選択した音符に適用する値です。"
        }
    }
}

enum StudioHelpTopic: String, CaseIterable, Identifiable {
    case workflow, clip, section, instrument, root, beat, velocity, pan, quantize, loop, envelope, save, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workflow: return "まずはデモを少し変える"
        case .clip: return "クリップとパート"
        case .section: return "セクション（曲の区切り）"
        case .instrument: return "サンプルと楽器"
        case .root: return "基準音（Root）と音程"
        case .beat: return "拍・テンポ・繰り返し"
        case .velocity: return "強弱（ベロシティ）と音量"
        case .pan: return "パン（左右の配置）"
        case .quantize: return "拍に揃える（クオンタイズ）"
        case .loop: return "ループとクロスフェード"
        case .envelope: return "立ち上がりと余韻（ADSR）"
        case .save: return "保存とWAV書き出しの違い"
        case .ai: return "AIの演奏案と編曲案"
        }
    }
    var explanation: String {
        switch self {
        case .workflow: return "空の構成なら「デモ曲」で開始。「全体を再生」で聴いて「全停止」。クリップを選び、下段で音符の音程・長さ・強弱を変更して「適用」。もう一度聴き、構成を保存します。サビ帯→「選択区切り」→範囲再生で繰り返し聴けます。一時停止して編集し、再生で聴き比べます。拍目盛りクリックで途中へ移動できます。上段の矢印で曲全体の編集、下段の矢印で選択クリップの音符編集を取り消し・やり直しできます。"
        case .clip: return "クリップは一まとまりの演奏です。パートは一つの楽器を担当する行で、同じ行のクリップは音色と音量を共有します。クリップを選ぶと右に設定、下に音符を表示します。"
        case .section: return "イントロ・Aメロ・サビなどの区切りです。上部の帯を選ぶと、右側で名前・長さ・順番を調整できます。開始拍は選んだ区切り内の位置で、「曲の先頭から」は曲頭を基準にします。"
        case .instrument: return "サンプルは楽器の材料になる短い音。楽器は、その音と基準音・ADSR・ループ設定をまとめたものです。「波形・楽器を編集…」でWAVから音を切り出せます。混ざった曲からの楽器の音源分離は未対応です。"
        case .root: return "元のサンプルをどの音程の鍵盤へ対応させるかを決めます。音程の自動検出ではありません。音符の音程はMIDI番号（60＝C4）、移調は半音数（12＝1オクターブ）です。"
        case .beat: return "1拍は四分音符1個分。BPMは1分間の拍数で、大きいほど速くなります。クリップの繰り返しは演奏を指定回数並べる設定で、素材のループとは別です。"
        case .velocity: return "強弱は音符ごとの発音の強さ（1〜127）。クリップの強弱%はその倍率、パート音量は同じ楽器の全クリップの音量、全体音量は曲全体の出力です。"
        case .pan: return "パート全体の音を左右へ配置します。左−100%・中央・右100%。同じパートの全クリップで共通です。再生中も調整でき、中央ボタンで戻せます。構成保存とWAVにも反映します。「左右配置デモ」で試せます。"
        case .quantize: return "選んだ音符の開始を目盛りへ揃えます。1/4は1拍、1/8は半拍、1/16は¼拍。Tは3連符です。長さ・音程・強弱は保ち、音符編集の取り消しで戻せます。"
        case .loop: return "素材の一部分を繰り返して音を伸ばします。継ぎ目（クロスフェード）は末尾と先頭を少し重ね、クリック音を減らします。設定は同じパートの全クリップへ適用されます。"
        case .envelope: return "立ち上がり（Attack）は最大音量までの時間、減衰（Decay）は保持音量へ下がる時間、保持音量（Sustain）は押鍵中の音量、余韻（Release）は離鍵後に消えるまでの時間です。ペダルで音を保持する操作とは別です。"
        case .save: return "構成保存（.sfensemble）は音源・演奏・配置を含み、制作を再開できます。楽器保存（.sfinstrument）は音色、演奏保存（.sfperformance）は音符を保存します。WAVは聴くための音声です。素材編集画面のWAV書き出しは選択素材、構成画面では曲全体が対象です。"
        case .ai: return "AI演奏は短い音符の候補、AI編曲は既存の楽器を使うセクションと演奏の候補です。採用後も手で編集できます。編曲の採用は構成全体を置き換えます。上段の曲の取り消しで採用前へ戻せます。履歴は再起動すると消えるため、元を残すなら別名で保存してください。「デモ」はAIを呼ばない固定例です。"
        }
    }
}

struct StudioHelpButton: View {
    var wood: WorkspaceWood = .walnut
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label("使い方", systemImage: "questionmark.circle") }
            .accessibilityIdentifier("help.guide").accessibilityLabel("使い方と用語を開く")
            .help("操作の流れや、クリップ・強弱・ADSRなどの用語を確認できます。")
            .popover(isPresented: $showing) { StudioHelpView(wood: wood) }
    }
}

private struct StudioHelpView: View {
    let wood: WorkspaceWood
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var topics: [StudioHelpTopic] {
        StudioHelpTopic.allCases.filter { query.isEmpty || ($0.title + $0.explanation).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("使い方と用語").font(.system(size: 17, weight: .medium))
                Spacer()
                Button("閉じる") { dismiss() }
            }.padding(16).foregroundStyle(wood.ink).background(WoodSurface(wood: wood, horizontalGrain: true))
            TextField("用語や機能を検索", text: $query).textFieldStyle(.roundedBorder).padding(12)
                .accessibilityIdentifier("help.search").accessibilityLabel("使い方と用語を検索")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if topics.isEmpty { Text("一致する説明がありません。別の言葉で検索してください。").foregroundStyle(.secondary) }
                    ForEach(topics) { topic in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(topic.title).font(.system(size: 13, weight: .semibold))
                            Text(topic.explanation).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(16)
            }
        }.frame(width: 470, height: 540).background(Color(red: 0.10, green: 0.12, blue: 0.095))
            .buttonStyle(CabinetButton()).preferredColorScheme(.dark)
    }
}

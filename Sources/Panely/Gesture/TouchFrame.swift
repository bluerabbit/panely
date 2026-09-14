import Foundation

/// トラックパッドの 1 フレーム分の接触点。MultitouchService が MTTouch から変換して渡す。
/// 認識器はデバイス単位で持つため、デバイス ID はここに含めない。
struct TouchFrame {
    /// 接触中の点 1 つ。x, y は 0...1 の正規化座標（CMultitouch.h の定義では左下原点）。
    struct Touch {
        let id: Int32
        let x: Double
        let y: Double
    }

    let timestamp: TimeInterval
    /// 接触中（stage == touching）の点だけを入れる
    let touches: [Touch]
}

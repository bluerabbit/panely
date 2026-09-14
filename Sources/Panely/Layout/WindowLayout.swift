import CoreGraphics

/// 配置と画面の visibleFrame から、ウインドウの新しい frame を計算する純粋関数。
enum WindowLayout {
    /// visibleFrame は AppKit 座標（左下原点）。戻り値も AppKit 座標。AX 座標への変換は Services 側で行う。
    static func frame(for action: WindowAction, in visibleFrame: CGRect) -> CGRect {
        // 幅が奇数のとき左右で 1px 差が出るが、切り捨てを共有するので隙間も重なりも出ない
        let half = (visibleFrame.width / 2).rounded(.down)
        switch action {
        case .maximize:
            return visibleFrame
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: half, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.minX + half, y: visibleFrame.minY,
                          width: visibleFrame.width - half, height: visibleFrame.height)
        }
    }
}

import AppKit
import ApplicationServices
import os

/// 統合ログは動的な文字列を既定で秘匿するため、読めるように public を指定する。
/// 読み方: /usr/bin/log show --last 10m --predicate 'subsystem == "com.bluerabbit.panely"'
private let logger = Logger(subsystem: "com.bluerabbit.panely", category: "accessibility")

/// AX API で対象ウインドウを取り、位置と大きさを書く。AX に触るのはこのクラスだけ。
final class AccessibilityService {
    init() {
        // 相手アプリが固まっていると既定の 6 秒間ブロックされるため、1 秒で諦める
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    }

    func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// フォーカス中のウインドウと、それが乗っている画面。
    /// 自分自身、ネイティブフルスクリーン中、位置や大きさを持たないウインドウは nil。
    func focusedWindow() -> (window: AXUIElement, screen: NSScreen)? {
        guard let pid = focusedApplicationPID(), pid != getpid() else {
            logger.error("フォーカス中のアプリが取れない、または自分自身")
            return nil
        }
        guard let window = windowElement(of: AXUIElementCreateApplication(pid)) else {
            logger.error("pid=\(pid, privacy: .public) のウインドウが取れない")
            return nil
        }
        guard !isFullScreen(window) else {
            logger.notice("pid=\(pid, privacy: .public) はフルスクリーン中")
            return nil
        }
        guard let axFrame = readFrame(of: window) else {
            logger.error("pid=\(pid, privacy: .public) のウインドウ位置・大きさが読めない")
            return nil
        }
        guard let screen = screen(containing: axFrame) else {
            logger.error("pid=\(pid, privacy: .public) のウインドウ \(describe(axFrame), privacy: .public) が乗る画面が無い")
            return nil
        }
        return (window, screen)
    }

    /// AppKit 座標の frame を AX 座標に変換して書き込む。
    func setFrame(_ frame: CGRect, for window: AXUIElement) {
        let origin = axOrigin(for: frame)
        let target = CGRect(origin: origin, size: frame.size)
        let before = readFrame(of: window)
        write(origin: origin, size: frame.size, to: window)

        // 最小サイズなどで拒まれたら 1 回だけやり直す。非同期に位置を戻すアプリがあるため少し待つ
        var actual = readFrame(of: window)
        if let current = actual, !isClose(current, to: target) {
            usleep(50_000)
            write(origin: origin, size: frame.size, to: window)
            actual = readFrame(of: window)
        }

        let result = actual.map(describe) ?? "読めない"
        let beforeText = before.map(describe) ?? "読めない"
        // info は既定でディスクに残らないので notice にする
        if let actual, isClose(actual, to: target) {
            logger.notice("配置 前=\(beforeText, privacy: .public) 後=\(result, privacy: .public)")
            return
        }
        logger.error("配置がずれたまま 前=\(beforeText, privacy: .public) 目標=\(describe(target), privacy: .public) 実際=\(result, privacy: .public)")
    }

    // MARK: - 対象の決定

    /// NSWorkspace.frontmostApplication はホットキー直後に遅れることがあるので AX を先に見る。
    /// Chrome では AX が失敗するので、そのときだけ NSWorkspace を使う
    private func focusedApplicationPID() -> pid_t? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                                   kAXFocusedApplicationAttribute as CFString, &value)
        if result == .success, let element = value {
            var pid: pid_t = 0
            if AXUIElementGetPid(element as! AXUIElement, &pid) == .success { return pid }
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        logger.notice("AX のフォーカスアプリ取得に失敗 code=\(result.rawValue, privacy: .public)、NSWorkspace の \(frontmost?.localizedName ?? "nil", privacy: .public) を使う")
        return frontmost?.processIdentifier
    }

    /// フォーカス → メイン → ウインドウ一覧の先頭、の順で探す
    private func windowElement(of app: AXUIElement) -> AXUIElement? {
        if let focused = copyElement(app, kAXFocusedWindowAttribute) { return focused }
        if let main = copyElement(app, kAXMainWindowAttribute) { return main }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    /// ネイティブフルスクリーン中は AX で動かせないので対象外にする
    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    /// ウインドウと交差面積が最大の画面
    private func screen(containing axFrame: CGRect) -> NSScreen? {
        let frame = appKitFrame(for: axFrame)
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = frame.intersection(screen.frame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen
    }

    // MARK: - 座標変換（AX はプライマリ画面の左上原点で y が下向き）

    private var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private func axOrigin(for frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
    }

    private func appKitFrame(for axFrame: CGRect) -> CGRect {
        CGRect(x: axFrame.minX, y: primaryMaxY - axFrame.maxY, width: axFrame.width, height: axFrame.height)
    }

    // MARK: - 読み書き

    private func readFrame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copyAXValue(window, kAXPositionAttribute, expecting: .cgPoint),
              let sizeValue = copyAXValue(window, kAXSizeAttribute, expecting: .cgSize) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func copyAXValue(_ window: AXUIElement, _ attribute: String, expecting type: AXValueType) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == type else { return nil }
        return axValue
    }

    /// 位置 → 大きさ → 位置 の順に書く。先に動かして広がる余地を作り、
    /// 大きさ変更で位置を戻すアプリのために最後にもう一度位置を書く
    private func write(origin: CGPoint, size: CGSize, to window: AXUIElement) {
        var origin = origin
        var size = size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        let first = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let second = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        if first != .success || sized != .success || second != .success {
            logger.error("AX 書き込みエラー 位置=\(first.rawValue, privacy: .public) 大きさ=\(sized.rawValue, privacy: .public) 位置=\(second.rawValue, privacy: .public)")
        }
    }

    private func isClose(_ a: CGRect, to b: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// ログ用の短い表記。Logger の補間はクロージャ扱いなので、self を要求しないファイル関数にする
private func describe(_ rect: CGRect) -> String {
    "(\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))x\(Int(rect.height)))"
}

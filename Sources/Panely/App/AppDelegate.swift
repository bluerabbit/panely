import AppKit
import Carbon

/// サービスを所有して配線する。ホットキーもジェスチャーも perform(_:) に集約する。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 既定のショートカット。v1 では設定 UI を持たず、変更はここを書き換えて再ビルドする
    static let shortcuts: [HotKeyShortcut: WindowAction] = [
        HotKeyShortcut(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey | optionKey)): .maximize,
        HotKeyShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey)): .leftHalf,
        HotKeyShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey)): .rightHalf,
    ]

    private let accessibility = AccessibilityService()
    private var hotKeys: HotKeyService?
    private var multitouch: MultitouchService?
    /// タッチ ID はデバイスごとに振られるので、認識器もデバイスごとに持つ
    private var recognizers: [UInt: GestureRecognizer] = [:]
    private var statusItem: NSStatusItem?
    private lazy var permissionWindow = PermissionWindowController(
        isTrusted: { [accessibility] in accessibility.isTrusted(prompt: false) },
        openSettings: { [weak self] in self?.openAccessibilitySettings() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ensureTrusted()
        hotKeys = HotKeyService(shortcuts: Self.shortcuts) { [weak self] action in
            self?.perform(action)
        }
        multitouch = MultitouchService { [weak self] deviceID, frame in
            self?.handle(deviceID: deviceID, frame: frame)
        }
        multitouch?.startAll()
        multitouch?.watchDeviceConnections()
        // スリープ復帰後はフレームが届かなくなるので列挙からやり直す
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        statusItem = makeStatusItem()
    }

    @objc private func workspaceDidWake() {
        recognizers.removeAll()
        multitouch?.startAll()
    }

    func perform(_ action: WindowAction) {
        guard ensureTrusted() else { return }
        guard let (window, screen) = accessibility.focusedWindow() else { return }
        let frame = WindowLayout.frame(for: action, in: screen.visibleFrame)
        accessibility.setFrame(frame, for: window)
    }

    // MARK: - アクセシビリティ許可

    /// 許可があれば true。無ければ案内ウインドウを出して false を返す
    private func ensureTrusted() -> Bool {
        if accessibility.isTrusted(prompt: false) { return true }
        // prompt 付きで一度呼ばないとシステム設定のアクセシビリティ一覧に Panely が載らない。
        // ウインドウが出ているあいだは繰り返さない（システムのダイアログが何枚も出るため）
        if permissionWindow.window?.isVisible != true {
            _ = accessibility.isTrusted(prompt: true)
        }
        permissionWindow.show()
        return false
    }

    // MARK: - ジェスチャー

    private func handle(deviceID: UInt, frame: TouchFrame) {
        let recognizer = recognizers[deviceID] ?? GestureRecognizer()
        recognizers[deviceID] = recognizer
        guard let gesture = recognizer.consume(frame) else { return }
        perform(Self.action(for: gesture))
    }

    private static func action(for gesture: Gesture) -> WindowAction {
        switch gesture {
        case .tap: return .maximize
        case .swipeLeft: return .leftHalf
        case .swipeRight: return .rightHalf
        }
    }

    // MARK: - メニューバー

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Panely")
        item.menu = makeMenu()
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // action なしの項目は無効表示になる。ショートカットの案内として使う
        for (shortcut, action) in Self.shortcuts.sorted(by: { $0.value.menuOrder < $1.value.menuOrder }) {
            menu.addItem(withTitle: "\(shortcut.displayString) / \(action.gestureName)  \(action.title)",
                         action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "アクセシビリティ設定を開く",
                     action: #selector(openAccessibilitySettings), keyEquivalent: "").target = self
        // macOS 側の 4 本指スワイプ（フルスクリーンアプリ間の移動）と衝突するため、3 本指に変えてもらう
        menu.addItem(withTitle: "スワイプが効かないときは「フルスクリーンアプリ間をスワイプ」を 3 本指に",
                     action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "トラックパッド設定を開く",
                     action: #selector(openTrackpadSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Panely を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// macOS の 4 本指スワイプと衝突するため、「フルスクリーンアプリ間をスワイプ」を 3 本指に変えてもらう導線
    @objc private func openTrackpadSettings() {
        open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension WindowAction {
    var title: String {
        switch self {
        case .maximize: return "最大化"
        case .leftHalf: return "左半分"
        case .rightHalf: return "右半分"
        }
    }

    var gestureName: String {
        switch self {
        case .maximize: return "4本指タップ"
        case .leftHalf: return "4本指←"
        case .rightHalf: return "4本指→"
        }
    }

    var menuOrder: Int {
        switch self {
        case .maximize: return 0
        case .leftHalf: return 1
        case .rightHalf: return 2
        }
    }
}

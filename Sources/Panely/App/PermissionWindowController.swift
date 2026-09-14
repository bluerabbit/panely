import AppKit

/// アクセシビリティ許可が無いときに出す案内ウインドウ。
/// 1 秒ごとに許可を確かめ、許可されたら自分で閉じる。
final class PermissionWindowController: NSWindowController {
    private let isTrusted: () -> Bool
    private let openSettings: () -> Void
    private var timer: Timer?

    init(isTrusted: @escaping () -> Bool, openSettings: @escaping () -> Void) {
        self.isTrusted = isTrusted
        self.openSettings = openSettings
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Panely"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("使わない")
    }

    /// 前面に出して監視を始める。すでに出ていれば前面に持ってくるだけ
    func show() {
        // メニューバー常駐アプリは activate しないとウインドウが背面に出る
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
    }

    private func poll() {
        guard isTrusted() else { return }
        close()
    }

    @objc private func openSettingsClicked() {
        openSettings()
    }

    // MARK: - レイアウト

    private func makeContentView() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Panely")!)
        icon.symbolConfiguration = .init(pointSize: 56, weight: .regular)
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "「アクセシビリティ」の許可が必要です")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.alignment = .center

        let body = wrappingLabel(
            "Panely はアクセシビリティ API を使って、他のアプリのウインドウの位置と大きさを変えます。"
            + "この許可がないとショートカットもジェスチャーも動きません。\n\n"
            + "下のボタンでシステム設定を開き、アクセシビリティの一覧で Panely を有効にしてください。"
            + "許可されるとこのウインドウは自動で閉じます。")

        let hint = wrappingLabel(
            "許可したのにこのウインドウが閉じない場合は、一覧の Panely を一度オフにしてから再度オンにしてください。"
            + "それでも変わらない場合は Panely を再起動してください。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let button = NSButton(title: "システム設定を開く", target: self, action: #selector(openSettingsClicked))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, title, body, makeWaitingIndicator(), hint, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 28, right: 32)
        stack.setCustomSpacing(8, after: icon)
        stack.setCustomSpacing(24, after: hint)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: 480),
        ])
        return container
    }

    /// 橙の丸と「許可を待っています…」。許可を監視中であることを示す
    private func makeWaitingIndicator() -> NSView {
        let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!)
        dot.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        dot.contentTintColor = .systemOrange

        let label = NSTextField(labelWithString: "許可を待っています…")
        label.font = .systemFont(ofSize: 13, weight: .semibold)

        let stack = NSStackView(views: [dot, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.preferredMaxLayoutWidth = 416
        return label
    }
}

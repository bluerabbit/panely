import AppKit

// LSUIElement は Info.plist 側で効かせる。swift run の裸バイナリでは Dock にタイルが出るが、
// フォールバックは書かない（.app バンドルだけをサポートする）。
let app = NSApplication.shared
// トップレベルの let で保持しないと delegate が解放される
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import Carbon

/// Carbon ホットキー 1 つ分。keyCode と修飾キーは Carbon の値（kVK_*, controlKey など）。
struct HotKeyShortcut: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// メニューに出す表記。v1 で使う 3 キーだけ名前を持ち、他は keyCode を出す
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    private var keyName: String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        default: return "Key \(keyCode)"
        }
    }
}

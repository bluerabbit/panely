import Carbon
import Foundation

/// Carbon の RegisterEventHotKey でグローバルショートカットを受け取る。
/// アクセシビリティ権限なしで動き、他アプリが前面でも届く。プロセスの寿命と同じなので解除処理は持たない。
final class HotKeyService {
    private let onAction: (WindowAction) -> Void
    /// EventHotKeyID.id → WindowAction。ハンドラで id から動作に戻す
    private var actions: [UInt32: WindowAction] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    init(shortcuts: [HotKeyShortcut: WindowAction], onAction: @escaping (WindowAction) -> Void) {
        self.onAction = onAction
        installHandler()
        for (index, (shortcut, action)) in shortcuts.enumerated() {
            register(shortcut, action: action, id: UInt32(index + 1))
        }
    }

    private func register(_ shortcut: HotKeyShortcut, action: WindowAction, id: UInt32) {
        // keyCode 0 は A キー。空のショートカットを登録すると通常入力で発火してしまう
        guard shortcut.keyCode != 0 || shortcut.modifiers != 0 else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Panely: ホットキー登録に失敗 %@ status=%d", shortcut.displayString, status)
            return
        }
        hotKeyRefs.append(ref)
        actions[id] = action
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            service.handle(id: hotKeyID.id)
            return noErr
        }, 1, &spec, userData, &handlerRef)
    }

    /// Carbon はアプリケーションターゲットのホットキーをメインスレッドで配送する
    private func handle(id: UInt32) {
        guard let action = actions[id] else { return }
        onAction(action)
    }

    /// "PNLY"
    private static let signature = OSType(0x504E_4C59)
}

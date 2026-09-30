import ServiceManagement
import os

private let logger = Logger(subsystem: "com.bluerabbit.panely", category: "loginItem")

/// ログイン時の自動起動。SMAppService は .app バンドルの現在の場所を登録するので、
/// /Applications などに置いてから有効にする前提
final class LoginItemService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 有効化後に利用者の承認待ち（requiresApproval）になったときは、
    /// 何も起きなかったように見えないようにシステム設定のログイン項目を開く
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("ログイン項目の更新に失敗: \(error.localizedDescription, privacy: .public)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

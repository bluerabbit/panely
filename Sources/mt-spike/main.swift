import CMultitouch
import Foundation

// MultitouchSupport.framework 検証用 CLI。
// 確認したいこと:
//   1. この macOS でコールバックが呼ばれるか
//   2. 権限（入力監視）なしで動くか
//   3. MTTouch のレイアウトが正しいか（x, y が 0...1 に収まり、stage が 4 で接触を表すか）
//   4. 4 本指のタップ / スワイプがフレーム列から素朴に判別できるか
//
// 使い方: swift run mt-spike [秒数]   （既定 30 秒で自動終了）

// MARK: - dlsym

typealias CreateListFn = @convention(c) () -> UnsafeMutableRawPointer?
typealias RegisterFn = @convention(c) (MTDeviceRef?, MTFrameCallbackFunction?) -> Bool
typealias StartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
typealias StopFn = @convention(c) (MTDeviceRef?) -> Void

let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
    fail("dlopen 失敗: \(String(cString: dlerror()))")
}

func symbol<T>(_ name: String, as type: T.Type) -> T {
    guard let sym = dlsym(handle, name) else {
        fail("dlsym 失敗: \(name) が見つかりません")
    }
    return unsafeBitCast(sym, to: type)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("NG: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let createList = symbol("MTDeviceCreateList", as: CreateListFn.self)
let register = symbol("MTRegisterContactFrameCallback", as: RegisterFn.self)
let start = symbol("MTDeviceStart", as: StartFn.self)
let stop = symbol("MTDeviceStop", as: StopFn.self)
print("OK: dlopen / dlsym 成功")

// MARK: - 統計（コールバックスレッドから触るのでロックで守る）

let lock = NSLock()
var frameCount = 0
var maxTouching = 0
var minX: Float = .infinity, maxX: Float = -.infinity
var minY: Float = .infinity, maxY: Float = -.infinity
var seenStages = Set<Int32>()
var lastPrintedCount = -1
var lastPrintTime: Double = 0

// 素朴な 4 本指判定。GestureRecognizer の設計を検証するためのもの。
var gestureStart: Double = 0
var gestureMaxFingers = 0
var landing: [Int32: MTPoint] = [:]
var latched = false

let callback: MTFrameCallbackFunction = { _, touches, numTouches, timestamp, _ in
    lock.lock()
    defer { lock.unlock() }
    frameCount += 1

    var touching: [MTTouch] = []
    if let touches {
        for touch in UnsafeBufferPointer(start: touches, count: Int(numTouches)) {
            seenStages.insert(touch.stage)
            guard touch.stage == kMTPathStageTouching else { continue }
            touching.append(touch)
            let p = touch.normalizedVector.position
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
    }
    maxTouching = max(maxTouching, touching.count)

    // 接触数が変わったとき、または 100ms ごとに 1 行出す
    let countChanged = touching.count != lastPrintedCount
    if countChanged || timestamp - lastPrintTime > 0.1 {
        lastPrintedCount = touching.count
        lastPrintTime = timestamp
        let detail = touching.map { t in
            let p = t.normalizedVector.position
            return String(format: "#%d(%.2f,%.2f)", t.identifier, p.x, p.y)
        }.joined(separator: " ")
        print(String(format: "t=%.3f n=%d raw=%d %@", timestamp, touching.count, numTouches, detail))
    }

    // --- 素朴な 4 本指判定 ---
    if touching.isEmpty {
        if gestureMaxFingers == 4, !latched {
            let elapsed = timestamp - gestureStart
            if elapsed < 0.3 { print(">>> 4本指タップ (\(Int(elapsed * 1000))ms)") }
        }
        gestureStart = 0
        gestureMaxFingers = 0
        landing.removeAll()
        latched = false
        return
    }
    if gestureStart == 0 { gestureStart = timestamp }
    gestureMaxFingers = max(gestureMaxFingers, touching.count)
    for t in touching where landing[t.identifier] == nil {
        landing[t.identifier] = t.normalizedVector.position
    }
    guard touching.count == 4, !latched else { return }
    // 各指の（現在位置 − 着地位置）の平均。重心差分だと着地順で跳ねる。
    var dx: Float = 0, dy: Float = 0
    for t in touching {
        let p = t.normalizedVector.position
        let l = landing[t.identifier]!
        dx += p.x - l.x
        dy += p.y - l.y
    }
    dx /= 4; dy /= 4
    if abs(dx) >= 0.15, abs(dy) < abs(dx) * 0.5 {
        latched = true
        print(">>> 4本指スワイプ \(dx > 0 ? "→ 右" : "← 左") (dx=\(String(format: "%.2f", dx)))")
    }
}

// MARK: - デバイス列挙と開始

guard let listPtr = createList() else {
    fail("MTDeviceCreateList が nil を返しました")
}
let list = Unmanaged<CFArray>.fromOpaque(listPtr).takeUnretainedValue()
let deviceCount = CFArrayGetCount(list)
print("OK: デバイス数 = \(deviceCount)")
guard deviceCount > 0 else {
    fail("トラックパッドが見つかりません")
}

var devices: [MTDeviceRef] = []
for i in 0..<deviceCount {
    guard let device = MTDeviceRef(CFArrayGetValueAtIndex(list, i)) else {
        fail("device[\(i)] が nil です")
    }
    let registered = register(device, callback)
    start(device, 0)
    print("  device[\(i)] register=\(registered)")
    devices.append(device)
}

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 30
print("\(Int(seconds)) 秒間タッチを記録します。トラックパッドを 4 本指でタップ / 左右スワイプしてください。")

// 5 秒経ってもフレームが 1 つも来なければ権限の可能性を案内する
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    lock.lock(); let n = frameCount; lock.unlock()
    if n == 0 {
        print("!! 5 秒間フレームが届いていません。トラックパッドに触れていない場合は触れてください。")
        print("!! 触れているのに届かない場合は「システム設定 > プライバシーとセキュリティ > 入力監視」でターミナルを許可して再実行してください。")
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    for d in devices { stop(d) }
    lock.lock()
    print("")
    print("=== 結果 ===")
    print("フレーム数: \(frameCount)")
    print("同時接触の最大数: \(maxTouching)")
    print("観測した stage の値: \(seenStages.sorted())  （4 = Touching を期待）")
    if frameCount > 0, maxTouching > 0 {
        print(String(format: "x の範囲: %.3f ... %.3f  y の範囲: %.3f ... %.3f （0...1 に収まることを期待）", minX, maxX, minY, maxY))
    }
    let layoutOK = maxTouching > 0 && minX >= 0 && maxX <= 1 && minY >= 0 && maxY <= 1
    print(frameCount == 0 ? "NG: コールバックが呼ばれませんでした" : (layoutOK ? "OK: レイアウトは妥当です" : "NG: 座標が 0...1 を外れています。MTTouch のレイアウトを疑ってください"))
    lock.unlock()
    exit(0)
}

RunLoop.main.run()

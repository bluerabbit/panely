import Foundation

/// 認識結果。ホットキーと同じ WindowAction に AppDelegate が対応づける。
enum Gesture {
    case tap
    case swipeLeft
    case swipeRight
}

/// TouchFrame の列から 4 本指のタップ / 左右スワイプを判定する小さなステートマシン。
/// 1 台のトラックパッドにつき 1 インスタンスを持つ（タッチ ID はデバイスごとに振られるため）。
final class GestureRecognizer {
    /// しきい値。実機で調整する前提の定数。移動量はいずれもパッド幅比。
    struct Thresholds {
        var requiredFingers = 4
        var tapMaxDuration: TimeInterval = 0.30
        var tapMaxTravel = 0.03
        var swipeMinTravel = 0.12
        var swipeMaxDuration: TimeInterval = 0.50
        /// |dy| / |dx| がこれ以上なら縦方向（Mission Control など）とみなして無視する
        var swipeMaxVerticalRatio = 0.5
    }

    /// 接触中の指の移動量。着地位置からの差分を指ごとに取り、平均したもの。
    private struct Travel {
        /// 符号つき平均。方向判定に使う
        var dx = 0.0
        var dy = 0.0
        /// 距離の平均。ピンチのように符号つき平均が打ち消し合う動きを「動いた」と扱うために使う
        var distance = 0.0
    }

    private struct Point {
        let x: Double
        let y: Double
    }

    private let thresholds: Thresholds

    private var startedAt: TimeInterval?
    private var fourFingersAt: TimeInterval?
    private var maxFingers = 0
    private var landings: [Int32: Point] = [:]
    private var latched = false
    /// 全指が離れたフレームには位置が無いので、直前フレームの移動量をタップ判定に使う
    private var lastTravel = Travel()

    init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    func consume(_ frame: TouchFrame) -> Gesture? {
        if frame.touches.isEmpty {
            return finish(at: frame.timestamp)
        }
        return track(frame)
    }

    // MARK: - 接触中

    private func track(_ frame: TouchFrame) -> Gesture? {
        let touches = frame.touches
        if startedAt == nil {
            startedAt = frame.timestamp
        }
        for touch in touches where landings[touch.id] == nil {
            landings[touch.id] = Point(x: touch.x, y: touch.y)
        }
        maxFingers = max(maxFingers, touches.count)
        if touches.count == thresholds.requiredFingers, fourFingersAt == nil {
            fourFingersAt = frame.timestamp
        }
        lastTravel = travel(of: touches)

        // ラッチ後は全指が離れるまで何も出さない
        guard !latched else { return nil }
        // 5 本置いて 1 本離した 4 本は対象外（maxFingers で弾く）
        guard touches.count == thresholds.requiredFingers,
              maxFingers == thresholds.requiredFingers,
              let fourFingersAt else { return nil }
        // 時間の起点は 4 本そろった時刻。置いてから少し止まってスワイプしても発火させるため
        guard frame.timestamp - fourFingersAt <= thresholds.swipeMaxDuration else { return nil }

        let dx = lastTravel.dx
        let dy = lastTravel.dy
        guard abs(dx) >= thresholds.swipeMinTravel,
              abs(dy) < abs(dx) * thresholds.swipeMaxVerticalRatio else { return nil }

        latched = true
        return dx > 0 ? .swipeRight : .swipeLeft
    }

    /// 各指の（現在位置 − 着地位置）を平均する。重心の差分は着地順で跳ねるので使わない
    private func travel(of touches: [TouchFrame.Touch]) -> Travel {
        var sum = Travel()
        for touch in touches {
            guard let landing = landings[touch.id] else { continue }
            let dx = touch.x - landing.x
            let dy = touch.y - landing.y
            sum.dx += dx
            sum.dy += dy
            sum.distance += (dx * dx + dy * dy).squareRoot()
        }
        let count = Double(touches.count)
        return Travel(dx: sum.dx / count, dy: sum.dy / count, distance: sum.distance / count)
    }

    // MARK: - 全指が離れた

    private func finish(at timestamp: TimeInterval) -> Gesture? {
        guard let startedAt else { return nil }
        defer { reset() }

        guard !latched,
              maxFingers == thresholds.requiredFingers,
              timestamp - startedAt <= thresholds.tapMaxDuration,
              lastTravel.distance < thresholds.tapMaxTravel else { return nil }
        return .tap
    }

    private func reset() {
        startedAt = nil
        fourFingersAt = nil
        maxFingers = 0
        landings.removeAll()
        latched = false
        lastTravel = Travel()
    }
}

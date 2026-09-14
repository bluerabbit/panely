import XCTest
@testable import Panely

final class GestureRecognizerTests: XCTestCase {
    /// 4 本指の着地位置。横一列に並べる
    private let base: [(id: Int32, x: Double, y: Double)] = [
        (1, 0.30, 0.50), (2, 0.40, 0.50), (3, 0.50, 0.50), (4, 0.60, 0.50),
    ]

    // MARK: - タップ

    func testFourFingerTapWithin200ms() {
        let gestures = feed([
            frame(0.00, base),
            frame(0.10, base),
            frame(0.20, []),
        ])
        XCTAssertEqual(gestures, [.tap])
    }

    func testTapToleratesSmallJitter() {
        let gestures = feed([
            frame(0.00, base),
            frame(0.10, shifted(base, dx: 0.01, dy: 0.01)),
            frame(0.20, []),
        ])
        XCTAssertEqual(gestures, [.tap])
    }

    func testSequentialLandingAtDifferentXIsStillTap() {
        // 4 点が異なる x に 80ms かけて順に着地する。重心は右へ跳ぶが各指は動いていない
        let gestures = feed([
            frame(0.00, Array(base[0..<1])),
            frame(0.03, Array(base[0..<2])),
            frame(0.06, Array(base[0..<3])),
            frame(0.08, base),
            frame(0.15, base),
            frame(0.20, []),
        ])
        XCTAssertEqual(gestures, [.tap])
    }

    func testLongHoldIsNotTap() {
        let gestures = feed([
            frame(0.00, base),
            frame(0.40, base),
            frame(0.50, []),
        ])
        XCTAssertEqual(gestures, [])
    }

    func testThreeFingerTapIsIgnored() {
        let three = Array(base[0..<3])
        XCTAssertEqual(feed([frame(0.00, three), frame(0.15, [])]), [])
    }

    func testFiveFingerTapIsIgnored() {
        let five = base + [(id: 5, x: 0.70, y: 0.30)]
        XCTAssertEqual(feed([frame(0.00, five), frame(0.15, [])]), [])
    }

    // MARK: - スワイプ

    func testSwipeRight() {
        XCTAssertEqual(feed(swipe(dx: 0.20, dy: 0.0)), [.swipeRight])
    }

    func testSwipeLeft() {
        XCTAssertEqual(feed(swipe(dx: -0.20, dy: 0.0)), [.swipeLeft])
    }

    func testThreeFingerSwipeIsIgnored() {
        let three = Array(base[0..<3])
        let gestures = feed([
            frame(0.00, three),
            frame(0.15, shifted(three, dx: 0.10, dy: 0)),
            frame(0.30, shifted(three, dx: 0.20, dy: 0)),
            frame(0.35, []),
        ])
        XCTAssertEqual(gestures, [])
    }

    func testVerticalSwipeIsIgnored() {
        // Mission Control の 4 本指上スワイプ
        XCTAssertEqual(feed(swipe(dx: 0.0, dy: 0.20)), [])
    }

    func testDiagonalSwipeIsIgnored() {
        // |dy| >= |dx| * 0.5 は縦方向とみなす
        XCTAssertEqual(feed(swipe(dx: 0.20, dy: 0.12)), [])
    }

    func testPinchIsIgnored() {
        // Launchpad の寄せる動き。各指は 0.2 動くが符号つき平均はほぼ 0 になる。タップにもしない
        let center = 0.45
        let converged = base.map { t in
            (id: t.id, x: t.x + (t.x < center ? 0.20 : -0.20), y: t.y)
        }
        let gestures = feed([
            frame(0.00, base),
            frame(0.12, converged),
            frame(0.25, []),
        ])
        XCTAssertEqual(gestures, [])
    }

    func testSwipeAfterFifthFingerLiftedIsIgnored() {
        // 親指を置いたまま 5 本で始め、1 本離して 4 本で振っても発火しない
        let five = base + [(id: 5, x: 0.70, y: 0.30)]
        let gestures = feed([
            frame(0.00, five),
            frame(0.05, base),
            frame(0.20, shifted(base, dx: 0.20, dy: 0)),
            frame(0.30, []),
        ])
        XCTAssertEqual(gestures, [])
    }

    func testSwipeLatchesUntilAllFingersLift() {
        // 発火後に指がさらに動いても、離しても、2 回目は出ない
        let gestures = feed([
            frame(0.00, base),
            frame(0.15, shifted(base, dx: 0.15, dy: 0)),
            frame(0.25, shifted(base, dx: 0.25, dy: 0)),
            frame(0.30, shifted(base, dx: 0.30, dy: 0)),
            frame(0.35, []),
        ])
        XCTAssertEqual(gestures, [.swipeRight])
    }

    func testSwipeSlowerThanMaxDurationIsIgnored() {
        let gestures = feed([
            frame(0.00, base),
            frame(0.30, shifted(base, dx: 0.05, dy: 0)),
            frame(0.60, shifted(base, dx: 0.20, dy: 0)),
            frame(0.70, []),
        ])
        XCTAssertEqual(gestures, [])
    }

    func testSwipeDurationIsMeasuredFromFourFingersLanding() {
        // 指が順に着地して 4 本そろうまで 0.3 秒かかっても、そこから 0.5 秒以内なら発火する
        let gestures = feed([
            frame(0.00, Array(base[0..<1])),
            frame(0.10, Array(base[0..<2])),
            frame(0.20, Array(base[0..<3])),
            frame(0.30, base),
            frame(0.50, shifted(base, dx: 0.05, dy: 0)),
            frame(0.70, shifted(base, dx: 0.20, dy: 0)),
            frame(0.80, []),
        ])
        XCTAssertEqual(gestures, [.swipeRight])
    }

    // MARK: - 状態のリセット

    func testRecognizesConsecutiveGestures() {
        let gestures = feed([
            frame(0.00, base),
            frame(0.10, []),
            frame(0.50, []),
            frame(1.00, base),
            frame(1.20, shifted(base, dx: -0.20, dy: 0)),
            frame(1.30, []),
            frame(2.00, base),
            frame(2.10, []),
        ])
        XCTAssertEqual(gestures, [.tap, .swipeLeft, .tap])
    }

    func testIdleFramesProduceNothing() {
        XCTAssertEqual(feed([frame(0.0, []), frame(0.1, [])]), [])
    }

    // MARK: - ヘルパー

    private func feed(_ frames: [TouchFrame]) -> [Gesture] {
        let recognizer = GestureRecognizer()
        return frames.compactMap { recognizer.consume($0) }
    }

    private func frame(_ t: TimeInterval, _ points: [(id: Int32, x: Double, y: Double)]) -> TouchFrame {
        TouchFrame(timestamp: t, touches: points.map { TouchFrame.Touch(id: $0.id, x: $0.x, y: $0.y) })
    }

    private func shifted(_ points: [(id: Int32, x: Double, y: Double)], dx: Double, dy: Double)
        -> [(id: Int32, x: Double, y: Double)] {
        points.map { (id: $0.id, x: $0.x + dx, y: $0.y + dy) }
    }

    /// 4 本が同時に着地し、300ms で (dx, dy) だけ動いて離れる
    private func swipe(dx: Double, dy: Double) -> [TouchFrame] {
        [
            frame(0.00, base),
            frame(0.15, shifted(base, dx: dx / 2, dy: dy / 2)),
            frame(0.30, shifted(base, dx: dx, dy: dy)),
            frame(0.35, []),
        ]
    }
}

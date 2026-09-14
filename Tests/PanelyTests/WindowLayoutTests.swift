import XCTest
@testable import Panely

final class WindowLayoutTests: XCTestCase {
    func testMaximizeReturnsVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(WindowLayout.frame(for: .maximize, in: visible), visible)
    }

    func testHalvesOnEvenWidth() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(WindowLayout.frame(for: .leftHalf, in: visible),
                       CGRect(x: 0, y: 0, width: 720, height: 875))
        XCTAssertEqual(WindowLayout.frame(for: .rightHalf, in: visible),
                       CGRect(x: 720, y: 0, width: 720, height: 875))
    }

    func testHalvesOnOddWidthLeaveNoGapOrOverlap() {
        let visible = CGRect(x: 0, y: 0, width: 1441, height: 875)
        let left = WindowLayout.frame(for: .leftHalf, in: visible)
        let right = WindowLayout.frame(for: .rightHalf, in: visible)
        XCTAssertEqual(left.width, 720)
        XCTAssertEqual(right.width, 721)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, visible.width)
    }

    func testHalvesRespectOriginOfExternalDisplay() {
        // 外部ディスプレイは原点が 0 でない。メニューバーと Dock の分だけ visibleFrame も縮む
        let visible = CGRect(x: -2560, y: 100, width: 2560, height: 1340)
        let left = WindowLayout.frame(for: .leftHalf, in: visible)
        let right = WindowLayout.frame(for: .rightHalf, in: visible)
        XCTAssertEqual(left, CGRect(x: -2560, y: 100, width: 1280, height: 1340))
        XCTAssertEqual(right, CGRect(x: -1280, y: 100, width: 1280, height: 1340))
    }
}

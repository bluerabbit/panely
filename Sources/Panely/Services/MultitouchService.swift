import CMultitouch
import CoreFoundation
import Foundation
import IOKit
import os

private let logger = Logger(subsystem: "com.bluerabbit.panely", category: "multitouch")

/// private な MultitouchSupport.framework からトラックパッドの接触フレームを受け取る。
/// 関数は dlsym で取り、構造体は CMultitouch の定義を使う。コールバックはバックグラウンドスレッドで
/// 呼ばれるので、TouchFrame への変換だけ済ませてメインスレッドへ渡す。
final class MultitouchService {
    private typealias CreateListFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias RegisterFn = @convention(c) (MTDeviceRef?, MTFrameCallbackFunction?) -> Bool
    private typealias StartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias StopFn = @convention(c) (MTDeviceRef?) -> Void

    /// タッチ ID はデバイスごとに振られるので、受け手はデバイスを区別できる必要がある
    typealias FrameHandler = (_ deviceID: UInt, _ frame: TouchFrame) -> Void

    private let createList: CreateListFn
    private let register: RegisterFn
    private let start: StartFn
    private let stop: StopFn
    private let onFrame: FrameHandler
    private var devices: [MTDeviceRef] = []
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0

    /// framework が読めない環境では nil。ホットキーだけで動き続けるため、ここで落とさない
    init?(onFrame: @escaping FrameHandler) {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            logger.error("dlopen 失敗: \(String(cString: dlerror()), privacy: .public)")
            return nil
        }
        guard let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else {
            logger.error("dlsym 失敗: MultitouchSupport の関数が見つからない")
            return nil
        }
        self.createList = unsafeBitCast(createList, to: CreateListFn.self)
        self.register = unsafeBitCast(register, to: RegisterFn.self)
        self.start = unsafeBitCast(start, to: StartFn.self)
        self.stop = unsafeBitCast(stop, to: StopFn.self)
        self.onFrame = onFrame
    }

    /// トラックパッドを列挙して受信を始める。スリープ復帰後の再列挙にも使う
    func startAll() {
        stopAll()
        guard let listPointer = createList() else {
            logger.error("MTDeviceCreateList が nil")
            return
        }
        let list = Unmanaged<CFArray>.fromOpaque(listPointer).takeUnretainedValue()
        for index in 0..<CFArrayGetCount(list) {
            guard let device = MTDeviceRef(CFArrayGetValueAtIndex(list, index)) else { continue }
            guard register(device, frameCallback) else {
                logger.error("device[\(index, privacy: .public)] のコールバック登録に失敗")
                continue
            }
            start(device, 0)
            devices.append(device)
        }
        MultitouchSink.shared.set(self)
        logger.notice("トラックパッド \(self.devices.count, privacy: .public) 台で受信開始")
    }

    func stopAll() {
        MultitouchSink.shared.set(nil)
        for device in devices { stop(device) }
        devices.removeAll()
    }

    /// トラックパッドが接続されたら再列挙する。Bluetooth の Magic Trackpad は起動後につながることがあるため。
    /// 通知はメインの RunLoop に載せるので、コールバックはメインスレッドで呼ばれる
    func watchDeviceConnections() {
        guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddMatchingNotification(port, kIOMatchedNotification,
                                                      IOServiceMatching("AppleMultitouchDevice"),
                                                      deviceMatchedCallback, refcon, &matchedIterator)
        guard result == KERN_SUCCESS else {
            logger.error("IOServiceAddMatchingNotification 失敗 \(result, privacy: .public)")
            return
        }
        // 最初の呼び出しで既存デバイスを消費しないと通知が有効にならない
        drain(matchedIterator)
    }

    /// 接続直後は MTDeviceCreateList に載らないことがあるので少し待って再列挙する
    fileprivate func deviceConnected() {
        drain(matchedIterator)
        logger.notice("トラックパッドの接続を検出、再列挙する")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startAll()
        }
    }

    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    /// バックグラウンドスレッドから呼ばれる。メインへ渡すのはここ
    fileprivate func deliver(deviceID: UInt, frame: TouchFrame) {
        DispatchQueue.main.async { [onFrame] in
            onFrame(deviceID, frame)
        }
    }
}

/// C コールバックに userData を渡せないため、受け手をここで 1 つだけ保持する。
/// コールバックスレッドとメインスレッドの両方から触るのでロックで守る
private final class MultitouchSink {
    static let shared = MultitouchSink()
    private let lock = NSLock()
    private var service: MultitouchService?

    func set(_ service: MultitouchService?) {
        lock.lock()
        self.service = service
        lock.unlock()
    }

    func current() -> MultitouchService? {
        lock.lock()
        defer { lock.unlock() }
        return service
    }
}

private let deviceMatchedCallback: IOServiceMatchingCallback = { refcon, _ in
    guard let refcon else { return }
    Unmanaged<MultitouchService>.fromOpaque(refcon).takeUnretainedValue().deviceConnected()
}

private let frameCallback: MTFrameCallbackFunction = { device, touches, numTouches, timestamp, _ in
    guard let device, let service = MultitouchSink.shared.current() else { return }
    var touching: [TouchFrame.Touch] = []
    if let touches {
        for touch in UnsafeBufferPointer(start: touches, count: Int(numTouches)) where touch.stage == kMTPathStageTouching {
            let position = touch.normalizedVector.position
            touching.append(TouchFrame.Touch(id: touch.identifier, x: Double(position.x), y: Double(position.y)))
        }
    }
    service.deliver(deviceID: UInt(bitPattern: device), frame: TouchFrame(timestamp: timestamp, touches: touching))
}

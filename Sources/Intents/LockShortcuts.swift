import Foundation
import AppIntents
import CoreBluetooth

// MARK: - 1. 门锁实体定义（供快捷指令参数列表选择）

struct SmartLockEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "智能门锁"
    static var defaultQuery = SmartLockEntityQuery()

    var id: UUID
    var name: String
    var macAddress: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(macAddress)"
        )
    }

    init(lock: SmartLock) {
        self.id = lock.id
        self.name = lock.name
        self.macAddress = lock.macAddress
    }
}

struct SmartLockEntityQuery: EntityQuery {
    private static let storageKey = "saved_ttlocks_v1"

    static func loadSavedLocks() -> [SmartLock] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let locks = try? JSONDecoder().decode([SmartLock].self, from: data) else {
            return []
        }
        return locks
    }

    func entities(for identifiers: [UUID]) async throws -> [SmartLockEntity] {
        let locks = Self.loadSavedLocks()
        return locks
            .filter { identifiers.contains($0.id) }
            .map { SmartLockEntity(lock: $0) }
    }

    func suggestedEntities() async throws -> [SmartLockEntity] {
        return Self.loadSavedLocks().map { SmartLockEntity(lock: $0) }
    }

    func defaultResult() async -> SmartLockEntity? {
        guard let first = Self.loadSavedLocks().first else { return nil }
        return SmartLockEntity(lock: first)
    }
}

// MARK: - 2. 独立快捷指令：打开门锁（后台静默运行）

struct UnlockSmartLockIntent: AppIntent {
    static var title: LocalizedStringResource = "打开门锁"
    static var description = IntentDescription("通过蓝牙在后台自动连接指定门锁并执行开锁，无需打开 App 界面。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "门锁", description: "选择要开启的智能门锁")
    var lock: SmartLockEntity

    static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$lock)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = SmartLockEntityQuery.loadSavedLocks().first(where: { $0.id == lock.id }) else {
            throw ShortcutLockError.lockNotFound
        }
        try await HeadlessLockBLEExecutor.run(isUnlock: true, on: target)
        return .result(dialog: "已打开「\(target.name)」")
    }
}

// MARK: - 3. 独立快捷指令：关闭门锁（后台静默运行）

struct LockSmartLockIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭门锁"
    static var description = IntentDescription("通过蓝牙在后台自动连接指定门锁并执行闭锁，无需打开 App 界面。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "门锁", description: "选择要关闭的智能门锁")
    var lock: SmartLockEntity

    static var parameterSummary: some ParameterSummary {
        Summary("关闭 \(\.$lock)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = SmartLockEntityQuery.loadSavedLocks().first(where: { $0.id == lock.id }) else {
            throw ShortcutLockError.lockNotFound
        }
        try await HeadlessLockBLEExecutor.run(isUnlock: false, on: target)
        return .result(dialog: "已关闭「\(target.name)」")
    }
}

// MARK: - 4. 系统快捷指令 App 快捷入口注册

struct TTLockShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UnlockSmartLockIntent(),
            phrases: [
                "用\(.applicationName)打开\(\.$lock)",
                "使用\(.applicationName)开锁\(\.$lock)"
            ],
            shortTitle: "打开门锁",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: LockSmartLockIntent(),
            phrases: [
                "用\(.applicationName)关闭\(\.$lock)",
                "使用\(.applicationName)闭锁\(\.$lock)"
            ],
            shortTitle: "关闭门锁",
            systemImageName: "lock.fill"
        )
    }
}

// MARK: - 5. 门锁 iOS 蓝牙 UUID 持久化缓存（用于后台免扫描直连）

private enum PeripheralUUIDCache {
    private static let cacheKey = "ttlock_peripheral_uuid_map_v1"

    static func uuid(for mac: String) -> UUID? {
        let map = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        guard let str = map[mac.uppercased()] else { return nil }
        return UUID(uuidString: str)
    }

    static func save(uuid: UUID, for mac: String) {
        var map = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        map[mac.uppercased()] = uuid.uuidString
        UserDefaults.standard.set(map, forKey: cacheKey)
    }

    static func remove(for mac: String) {
        var map = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        map.removeValue(forKey: mac.uppercased())
        UserDefaults.standard.set(map, forKey: cacheKey)
    }
}

// MARK: - 6. 快捷指令专用后台无界面 BLE 执行器

private enum ShortcutLockError: LocalizedError {
    case lockNotFound
    case bluetoothUnavailable
    case timeout
    case connectFailed
    case serviceMissing
    case decryptFailed
    case rejected(UInt8)

    var errorDescription: String? {
        switch self {
        case .lockNotFound: return "未找到指定的门锁配置，请先在 App 中添加该门锁。"
        case .bluetoothUnavailable: return "手机蓝牙未开启或未授予蓝牙权限。"
        case .timeout: return "连接门锁超时，请确认手机处于门锁蓝牙范围内。"
        case .connectFailed: return "蓝牙连接门锁失败。"
        case .serviceMissing: return "未识别到门锁蓝牙控制服务。"
        case .decryptFailed: return "门锁响应数据解密失败，请检查密钥配置。"
        case .rejected(let code): return "门锁拒绝执行操作（错误码：\(code)）。"
        }
    }
}

private final class HeadlessLockBLEExecutor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private let targetLock: SmartLock
    private let isUnlock: Bool
    private let bleQueue = DispatchQueue(label: "com.local.smartlock.shortcut.ble")

    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    private var receiveBuffer: [UInt8] = []
    private var expectedFrameLength = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasCompleted = false
    private var isDirectConnecting = false

    private var timeoutWorkItem: DispatchWorkItem?
    private var fallbackScanWorkItem: DispatchWorkItem?

    private let serviceUUID = CBUUID(string: "00001910-0000-1000-8000-00805F9B34FB")
    private let txUUID = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")
    private let rxUUID = CBUUID(string: "0000FFF4-0000-1000-8000-00805F9B34FB")

    private init(lock: SmartLock, isUnlock: Bool) {
        self.targetLock = lock
        self.isUnlock = isUnlock
        super.init()
    }

    static func run(isUnlock: Bool, on lock: SmartLock) async throws {
        let executor = HeadlessLockBLEExecutor(lock: lock, isUnlock: isUnlock)
        try await executor.start()
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            bleQueue.async {
                self.continuation = cont
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: self.bleQueue,
                    options: [CBCentralManagerOptionShowPowerAlertKey: false]
                )

                // 后台扫描周期较长，整体超时设为 18 秒
                let timeout = DispatchWorkItem { [weak self] in
                    self?.complete(with: .failure(ShortcutLockError.timeout))
                }
                self.timeoutWorkItem = timeout
                self.bleQueue.asyncAfter(deadline: .now() + 18, execute: timeout)
            }
        }
    }

    private func startBackgroundScan() {
        guard !hasCompleted, centralManager.state == .poweredOn else { return }
        // 后台模式下不要传 AllowDuplicatesKey，避免系统忽略或降低扫描优先级
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func complete(with result: Result<Void, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        fallbackScanWorkItem?.cancel()
        fallbackScanWorkItem = nil

        if centralManager?.state == .poweredOn {
            centralManager.stopScan()
        }
        if let p = activePeripheral {
            p.delegate = nil
            centralManager.cancelPeripheralConnection(p)
        }
        centralManager?.delegate = nil
        activePeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil

        let cont = continuation
        continuation = nil
        cont?.resume(with: result)
    }

    private func sendCommand(_ command: TTLockCommand, payload: [UInt8]) {
        guard let peripheral = activePeripheral, let tx = txCharacteristic else { return }
        let chunks = TTLockCrypto.buildCommandPackets(command: command, payload: payload, lock: targetLock)
        for chunk in chunks {
            peripheral.writeValue(chunk, for: tx, type: .withResponse)
        }
    }

    private func handleFrame(_ frame: [UInt8]) {
        guard let parsed = TTLockCrypto.parseResponseFrame(frame, lock: targetLock) else {
            complete(with: .failure(ShortcutLockError.decryptFailed))
            return
        }

        guard parsed.success else {
            let errCode = parsed.data.count > 2 ? parsed.data[2] : 255
            complete(with: .failure(ShortcutLockError.rejected(errCode)))
            return
        }

        switch parsed.command {
        case TTLockCommand.checkUserTime.rawValue:
            guard parsed.data.count >= 6 else {
                complete(with: .failure(ShortcutLockError.decryptFailed))
                return
            }
            let r = (UInt32(parsed.data[2]) << 24) |
                    (UInt32(parsed.data[3]) << 16) |
                    (UInt32(parsed.data[4]) << 8)  |
                     UInt32(parsed.data[5])

            let payload = TTLockCrypto.controlLockPayload(
                unlockKey: targetLock.unlockKey,
                randomNumber: r,
                isUnlock: isUnlock
            )
            sendCommand(isUnlock ? .unlock : .lock, payload: payload)

        case TTLockCommand.unlock.rawValue, TTLockCommand.lock.rawValue:
            complete(with: .success(()))

        default:
            break
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !hasCompleted else { return }
        switch central.state {
        case .poweredOn:
            // 优先尝试通过缓存的 iOS 蓝牙设备 UUID 免扫描后台直连
            if let cachedUUID = PeripheralUUIDCache.uuid(for: targetLock.macAddress),
               let knownPeripheral = central.retrievePeripherals(withIdentifiers: [cachedUUID]).first {
                isDirectConnecting = true
                activePeripheral = knownPeripheral
                knownPeripheral.delegate = self
                central.connect(knownPeripheral, options: nil)

                // 若 4 秒内直连未成功（如缓存过期），自动取消并回退到扫描模式
                let fallback = DispatchWorkItem { [weak self] in
                    guard let self = self, !self.hasCompleted, self.isDirectConnecting else { return }
                    self.isDirectConnecting = false
                    if let p = self.activePeripheral {
                        self.centralManager.cancelPeripheralConnection(p)
                        self.activePeripheral = nil
                    }
                    self.startBackgroundScan()
                }
                fallbackScanWorkItem = fallback
                bleQueue.asyncAfter(deadline: .now() + 4, execute: fallback)
            } else {
                startBackgroundScan()
            }

        case .poweredOff, .unauthorized, .unsupported:
            complete(with: .failure(ShortcutLockError.bluetoothUnavailable))

        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !hasCompleted, activePeripheral == nil else { return }
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let bytes = [UInt8](mfgData)
        guard bytes.count >= 17 else { return }

        let macBytes = Array(bytes.suffix(6).reversed())
        let macStr = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")

        if macStr == targetLock.macAddress.uppercased() {
            // 缓存该门锁在当前 iPhone 上的蓝牙 UUID，供后续后台直接免扫描秒连
            PeripheralUUIDCache.save(uuid: peripheral.identifier, for: targetLock.macAddress)
            central.stopScan()
            activePeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !hasCompleted else { return }
        isDirectConnecting = false
        fallbackScanWorkItem?.cancel()
        fallbackScanWorkItem = nil
        PeripheralUUIDCache.save(uuid: peripheral.identifier, for: targetLock.macAddress)
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard !hasCompleted else { return }
        if isDirectConnecting {
            // 直连失败时清除旧缓存并无缝切入扫描模式
            isDirectConnecting = false
            fallbackScanWorkItem?.cancel()
            fallbackScanWorkItem = nil
            PeripheralUUIDCache.remove(for: targetLock.macAddress)
            activePeripheral = nil
            startBackgroundScan()
        } else {
            complete(with: .failure(ShortcutLockError.connectFailed))
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !hasCompleted else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            complete(with: .failure(ShortcutLockError.serviceMissing))
            return
        }
        peripheral.discoverCharacteristics([txUUID, rxUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !hasCompleted, let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == txUUID { txCharacteristic = c }
            if c.uuid == rxUUID { rxCharacteristic = c }
        }
        guard let rx = rxCharacteristic, txCharacteristic != nil else {
            complete(with: .failure(ShortcutLockError.serviceMissing))
            return
        }
        peripheral.setNotifyValue(true, for: rx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard !hasCompleted, characteristic.uuid == rxUUID, characteristic.isNotifying else { return }
        sendCommand(.checkUserTime, payload: TTLockCrypto.userAuthPayload())
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !hasCompleted, characteristic.uuid == rxUUID, let data = characteristic.value else { return }
        let chunk = [UInt8](data)

        if expectedFrameLength == 0 {
            guard chunk.count >= 12, chunk[0] == 0x7F, chunk[1] == 0x5A else { return }
            receiveBuffer.removeAll()
            expectedFrameLength = Int(chunk[11]) + 15
        }
        receiveBuffer.append(contentsOf: chunk)

        if expectedFrameLength > 0 && receiveBuffer.count >= expectedFrameLength {
            let completeFrame = Array(receiveBuffer.prefix(expectedFrameLength))
            receiveBuffer.removeAll()
            expectedFrameLength = 0
            handleFrame(completeFrame)
        }
    }
}
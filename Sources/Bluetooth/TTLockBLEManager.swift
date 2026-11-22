import Foundation
import CoreBluetooth
import UIKit

enum BLEAction {
    case unlock
    case lock
    case queryStatus
    case syncTime
}

@MainActor
final class TTLockBLEManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var isBusy = false
    @Published var statusText = "就绪"
    @Published var batteryLevel: Int?
    @Published var lockState: LockState = .unknown
    @Published var discoveredLocks: [DiscoveredLock] = []

    private var centralManager: CBCentralManager!
    private var peripheralMap: [String: CBPeripheral] = [:] // MAC -> CBPeripheral
    private var activePeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    private var targetLock: SmartLock?
    private var pendingAction: BLEAction?
    private var receiveBuffer: [UInt8] = []
    private var expectedFrameLength = 0
    private var timeoutTask: Task<Void, Never>?

    // TTLock 标准 GATT UUID
    private let serviceUUID = CBUUID(string: "00001910-0000-1000-8000-00805F9B34FB")
    private let txUUID = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")
    private let rxUUID = CBUUID(string: "0000FFF4-0000-1000-8000-00805F9B34FB")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusText = "请开启手机蓝牙"
            return
        }
        discoveredLocks.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    func execute(_ action: BLEAction, on lock: SmartLock) {
        guard centralManager.state == .poweredOn else {
            statusText = "请先打开系统蓝牙"
            return
        }
        guard !isBusy else { return }

        isBusy = true
        targetLock = lock
        pendingAction = action
        receiveBuffer.removeAll()
        expectedFrameLength = 0
        statusText = "正在搜索门锁..."

        startTimeout(seconds: 12)

        let targetMac = lock.macAddress.uppercased()
        if let cached = peripheralMap[targetMac] {
            statusText = "正在连接门锁..."
            activePeripheral = cached
            centralManager.connect(cached, options: nil)
        } else {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
        }
    }

    private func startTimeout(seconds: UInt64) {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if !Task.isCancelled && isBusy {
                finishOperation(message: "连接或响应超时，请靠近门锁重试", success: false)
            }
        }
    }

    private func finishOperation(message: String, success: Bool) {
        timeoutTask?.cancel()
        centralManager.stopScan()
        if let p = activePeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        activePeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        isBusy = false
        statusText = message

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(success ? .success : .error)
    }

    private func sendCommand(_ command: TTLockCommand, payload: [UInt8]) {
        guard let lock = targetLock,
              let peripheral = activePeripheral,
              let tx = txCharacteristic else { return }

        let chunks = TTLockCrypto.buildCommandPackets(command: command, payload: payload, lock: lock)
        for chunk in chunks {
            peripheral.writeValue(chunk, for: tx, type: .withResponse)
        }
    }

    private func handleCompleteFrame(_ frame: [UInt8]) {
        guard let lock = targetLock,
              let parsed = TTLockCrypto.parseResponseFrame(frame, lock: lock) else {
            finishOperation(message: "数据包解密失败，请核对 AES Key", success: false)
            return
        }

        if let bat = parsed.battery {
            batteryLevel = bat
        }

        guard parsed.success else {
            finishOperation(message: "门锁拒绝指令 (错误码: \(parsed.data[2]))", success: false)
            return
        }

        switch parsed.command {
        case TTLockCommand.checkUserTime.rawValue:
            // 提取 4 字节随机挑战数
            guard parsed.data.count >= 6 else {
                finishOperation(message: "鉴权响应异常", success: false)
                return
            }
            let r = (UInt32(parsed.data[2]) << 24) |
                    (UInt32(parsed.data[3]) << 16) |
                    (UInt32(parsed.data[4]) << 8)  |
                     UInt32(parsed.data[5])

            switch pendingAction {
            case .unlock:
                statusText = "正在开锁..."
                let payload = TTLockCrypto.controlLockPayload(unlockKey: lock.unlockKey, randomNumber: r, isUnlock: true)
                sendCommand(.unlock, payload: payload)
            case .lock:
                statusText = "正在闭锁..."
                let payload = TTLockCrypto.controlLockPayload(unlockKey: lock.unlockKey, randomNumber: r, isUnlock: false)
                sendCommand(.lock, payload: payload)
            case .syncTime:
                statusText = "正在校准时钟..."
                sendCommand(.correctTime, payload: TTLockCrypto.currentTimestampBytes())
            default:
                break
            }

        case TTLockCommand.unlock.rawValue:
            lockState = .unlocked
            finishOperation(message: "开锁成功", success: true)

        case TTLockCommand.lock.rawValue:
            lockState = .locked
            finishOperation(message: "闭锁成功", success: true)

        case TTLockCommand.getStatus.rawValue:
            let stateByte = parsed.data.count > 3 ? parsed.data[3] : 2
            lockState = (stateByte == 0) ? .locked : (stateByte == 1 ? .unlocked : .unknown)
            finishOperation(message: "状态已更新: \(lockState.rawValue)", success: true)

        case TTLockCommand.correctTime.rawValue:
            finishOperation(message: "门锁时钟已校准", success: true)

        default:
            break
        }
    }
}

extension TTLockBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state != .poweredOn {
                statusText = "蓝牙未开启"
                isBusy = false
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // 解析通通锁 ManufacturerData (17字节，末尾6字节倒序为真实MAC)
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let bytes = [UInt8](mfgData)
        guard bytes.count >= 17 else { return }

        let macBytes = Array(bytes.suffix(6).reversed())
        let macStr = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        let pType = bytes[0]
        let pVer = bytes[1]
        let scene = bytes[2]
        let battery = Int(bytes[4])
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "TTLock"

        Task { @MainActor in
            peripheralMap[macStr] = peripheral

            let item = DiscoveredLock(
                peripheralId: peripheral.identifier,
                macAddress: macStr,
                name: localName,
                rssi: RSSI.intValue,
                battery: battery,
                protocolType: pType,
                protocolVersion: pVer,
                scene: scene
            )
            if let idx = discoveredLocks.firstIndex(where: { $0.macAddress == macStr }) {
                discoveredLocks[idx] = item
            } else {
                discoveredLocks.append(item)
            }

            // 如果正在执行控制动作，匹配到目标 MAC 后立即停止扫描并连接
            if isBusy, let target = targetLock, target.macAddress.uppercased() == macStr {
                centralManager.stopScan()
                statusText = "已发现门锁，正在建立连接..."
                activePeripheral = peripheral
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            statusText = "正在读取蓝牙服务..."
            peripheral.delegate = self
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            finishOperation(message: "蓝牙连接失败", success: false)
        }
    }
}

extension TTLockBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
                finishOperation(message: "未找到门锁控制服务", success: false)
                return
            }
            peripheral.discoverCharacteristics([txUUID, rxUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let chars = service.characteristics else { return }
            for c in chars {
                if c.uuid == txUUID { txCharacteristic = c }
                if c.uuid == rxUUID { rxCharacteristic = c }
            }
            guard let rx = rxCharacteristic, txCharacteristic != nil else {
                finishOperation(message: "缺少通信特征值", success: false)
                return
            }
            peripheral.setNotifyValue(true, for: rx)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == rxUUID, characteristic.isNotifying else { return }
            if pendingAction == .queryStatus {
                statusText = "正在查询门锁状态..."
                sendCommand(.getStatus, payload: [])
            } else {
                statusText = "正在进行安全握手..."
                sendCommand(.checkUserTime, payload: TTLockCrypto.userAuthPayload())
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == rxUUID, let data = characteristic.value else { return }
        let chunk = [UInt8](data)

        Task { @MainActor in
            if expectedFrameLength == 0 {
                guard chunk.count >= 12, chunk[0] == 0x7F, chunk[1] == 0x5A else { return }
                receiveBuffer.removeAll()
                expectedFrameLength = Int(chunk[11]) + 15
            }
            receiveBuffer.append(contentsOf: chunk)

            if expectedFrameLength > 0 && receiveBuffer.count >= expectedFrameLength {
                let complete = Array(receiveBuffer.prefix(expectedFrameLength))
                receiveBuffer.removeAll()
                expectedFrameLength = 0
                handleCompleteFrame(complete)
            }
        }
    }
}
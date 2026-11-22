import Foundation
import Combine

struct SmartLock: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var macAddress: String       // 格式: XX:XX:XX:XX:XX:XX
    var aesKeyHex: String        // 32位十六进制字符串
    var unlockKey: UInt32        // 纯数字开锁密钥
    var adminPasscode: String?   // 可选管理员密码
    var protocolType: UInt8 = 5
    var protocolVersion: UInt8 = 3
    var scene: UInt8 = 2
    var groupId: UInt16 = 1
    var orgId: UInt16 = 1
}

enum LockState: String {
    case locked = "已上锁"
    case unlocked = "已解锁"
    case unknown = "状态未知"
}

struct DiscoveredLock: Identifiable, Equatable {
    var id: UUID { peripheralId }
    let peripheralId: UUID
    let macAddress: String
    let name: String
    let rssi: Int
    let battery: Int
    let protocolType: UInt8
    let protocolVersion: UInt8
    let scene: UInt8
}

@MainActor
final class LockStore: ObservableObject {
    @Published var locks: [SmartLock] = [] {
        didSet { save() }
    }
    @Published var selectedLockId: UUID?

    private let saveKey = "saved_ttlocks_v1"

    init() {
        load()
        if selectedLockId == nil {
            selectedLockId = locks.first?.id
        }
    }

    var selectedLock: SmartLock? {
        locks.first(where: { $0.id == selectedLockId }) ?? locks.first
    }

    func add(_ lock: SmartLock) {
        locks.append(lock)
        selectedLockId = lock.id
    }

    func delete(at offsets: IndexSet) {
        locks.remove(atOffsets: offsets)
        if selectedLock == nil {
            selectedLockId = locks.first?.id
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(locks) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([SmartLock].self, from: data) {
            locks = decoded
        }
    }
}
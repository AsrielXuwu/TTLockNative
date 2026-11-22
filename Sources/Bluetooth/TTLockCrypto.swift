import Foundation
import CommonCrypto

enum TTLockCommand: UInt8 {
    case getStatus = 20          // 0x14 查询开闭状态
    case checkRandom = 48        // 0x30 验证随机数
    case correctTime = 67        // 0x43 校准锁时间
    case unlock = 71             // 0x47 开锁
    case checkUserTime = 85      // 0x55 普通用户鉴权
    case lock = 88               // 0x58 闭锁
}

struct TTLockCrypto {
    // 插件 utils/transform.js 提取的完整 CRC8 查找表
    static let crcTable: [UInt8] = [
        0, 94, 188, 226, 97, 63, 221, 131, 194, 156, 126, 32, 163, 253, 31, 65,
        157, 195, 33, 127, 252, 162, 64, 30, 95, 1, 227, 189, 62, 96, 130, 220,
        35, 7, 159, 193, 66, 28, 254, 160, 225, 191, 93, 3, 128, 222, 60, 98,
        190, 224, 2, 92, 223, 129, 99, 61, 124, 34, 192, 158, 29, 67, 161, 255,
        70, 24, 250, 164, 39, 121, 155, 197, 132, 218, 56, 102, 229, 187, 89, 7,
        219, 133, 103, 57, 186, 228, 6, 88, 25, 71, 165, 251, 120, 38, 196, 154,
        101, 59, 217, 135, 4, 90, 184, 230, 167, 249, 27, 69, 198, 152, 122, 36,
        248, 166, 68, 26, 153, 199, 37, 123, 58, 100, 134, 216, 91, 5, 231, 185,
        140, 210, 48, 110, 237, 179, 81, 15, 78, 16, 242, 172, 47, 113, 147, 205,
        17, 79, 173, 243, 112, 46, 204, 146, 211, 141, 111, 49, 178, 236, 14, 80,
        175, 241, 19, 77, 206, 144, 114, 44, 109, 51, 209, 143, 12, 82, 176, 238,
        50, 108, 142, 208, 83, 13, 239, 177, 240, 174, 76, 18, 145, 207, 45, 115,
        202, 148, 118, 40, 171, 245, 23, 73, 8, 86, 180, 234, 105, 55, 213, 139,
        87, 9, 235, 181, 54, 104, 138, 212, 149, 203, 41, 119, 244, 170, 72, 22,
        233, 183, 85, 11, 136, 214, 52, 106, 43, 117, 151, 201, 74, 20, 246, 168,
        116, 42, 200, 150, 21, 75, 169, 247, 182, 232, 10, 84, 215, 137, 107, 53
    ]

    static func computeCRC(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for b in bytes {
            crc = crcTable[Int(crc ^ b)]
        }
        return crc
    }

    static func hexToBytes(_ hex: String) -> [UInt8] {
        let clean = hex.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let nextIdx = clean.index(idx, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            if nextIdx <= clean.endIndex, let byte = UInt8(clean[idx..<nextIdx], radix: 16) {
                bytes.append(byte)
            }
            idx = nextIdx
        }
        return bytes
    }

    static func aes128CBC(data: [UInt8], key: [UInt8], encrypt: Bool) -> [UInt8]? {
        guard key.count == 16 else { return nil }
        let operation = encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt)
        let bufferSize = data.count + kCCBlockSizeAES128
        var outBytes = [UInt8](repeating: 0, count: bufferSize)
        var numBytesProcessed: size_t = 0

        let status = CCCrypt(
            operation,
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            key, key.count,
            key, // TTLock 协议固定使用 AES Key 作为 IV
            data, data.count,
            &outBytes, bufferSize,
            &numBytesProcessed
        )

        guard status == kCCSuccess else { return nil }
        return Array(outBytes.prefix(numBytesProcessed))
    }

    /// 组包并切分为 20 字节的 BLE MTU 分片
    static func buildCommandPackets(command: TTLockCommand, payload: [UInt8], lock: SmartLock) -> [Data] {
        let aesKey = hexToBytes(lock.aesKeyHex)
        guard let encrypted = aes128CBC(data: payload, key: aesKey, encrypt: true) else { return [] }

        var frame: [UInt8] = [0x7F, 0x5A]
        frame.append(lock.protocolType)
        frame.append(lock.protocolVersion)
        frame.append(lock.scene)
        frame.append(UInt8((lock.groupId >> 8) & 0xFF))
        frame.append(UInt8(lock.groupId & 0xFF))
        frame.append(UInt8((lock.orgId >> 8) & 0xFF))
        frame.append(UInt8(lock.orgId & 0xFF))
        frame.append(command.rawValue)
        frame.append(0xAA) // ENCRYPT = -86 (0xAA)
        frame.append(UInt8(encrypted.count))
        frame.append(contentsOf: encrypted)

        let crc = computeCRC(frame)
        frame.append(crc)
        frame.append(0x13)
        frame.append(0x10)

        // 按 20 字节分包
        var chunks: [Data] = []
        var offset = 0
        while offset < frame.count {
            let end = min(offset + 20, frame.count)
            chunks.append(Data(frame[offset..<end]))
            offset = end
        }
        return chunks
    }

    /// 解密门锁返回的数据帧
    static func parseResponseFrame(_ frame: [UInt8], lock: SmartLock) -> (command: UInt8, success: Bool, battery: Int?, data: [UInt8])? {
        guard frame.count >= 15, frame[0] == 0x7F, frame[1] == 0x5A else { return nil }
        let cipherSlice = Array(frame[12..<(frame.count - 3)])
        let aesKey = hexToBytes(lock.aesKeyHex)
        guard let plain = aes128CBC(data: cipherSlice, key: aesKey, encrypt: false), plain.count >= 3 else {
            return nil
        }
        let cmd = plain[0]
        let isSuccess = plain[1] == 1
        let battery: Int? = isSuccess ? Int(plain[2]) : nil
        return (cmd, isSuccess, battery, plain)
    }

    // MARK: - 各类业务指令 Payload 生成

    static func userAuthPayload() -> [UInt8] {
        // 默认有效期 2000-01-01 00:00 至 2099-12-31 23:59，lockFlagPos=0，uid=0
        let start: [UInt8] = [0, 1, 1, 0, 0]
        let end: [UInt8] = [99, 12, 31, 23, 59]
        let flagPos: [UInt8] = [0, 0, 0]
        let uid: [UInt8] = [0, 0, 0, 0]
        return start + end + flagPos + uid
    }

    static func controlLockPayload(unlockKey: UInt32, randomNumber: UInt32, isUnlock: Bool) -> [UInt8] {
        let sum = unlockKey &+ randomNumber
        let sumBytes: [UInt8] = [
            UInt8((sum >> 24) & 0xFF),
            UInt8((sum >> 16) & 0xFF),
            UInt8((sum >> 8) & 0xFF),
            UInt8(sum & 0xFF)
        ]
        let nowSec = UInt32(Date().timeIntervalSince1970)
        let secBytes: [UInt8] = [
            UInt8((nowSec >> 24) & 0xFF),
            UInt8((nowSec >> 16) & 0xFF),
            UInt8((nowSec >> 8) & 0xFF),
            UInt8(nowSec & 0xFF)
        ]
        if isUnlock {
            return sumBytes + secBytes + currentTimestampBytes()
        } else {
            return sumBytes + secBytes
        }
    }

    static func currentTimestampBytes() -> [UInt8] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        return [
            UInt8((comps.year ?? 2026) - 2000),
            UInt8(comps.month ?? 1),
            UInt8(comps.day ?? 1),
            UInt8(comps.hour ?? 0),
            UInt8(comps.minute ?? 0),
            UInt8(comps.second ?? 0)
        ]
    }

    // MARK: - 直接从抓包 Base64 lockData 解析 (兼容一键导入)

    static func parseLockDataBase64(_ base64Str: String, customName: String = "我的门锁") -> SmartLock? {
        guard let rawData = Data(base64Encoded: base64Str.trimmingCharacters(in: .whitespacesAndNewlines)),
              rawData.count > 6 else { return nil }
        let bytes = [UInt8](rawData)
        let macBytes = Array(bytes.suffix(6))
        let cipherBytes = Array(bytes.prefix(bytes.count - 6))

        let macStr = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        let keyStr = String(macStr.prefix(9)) + String(macStr.dropFirst(10))
        let keyBytes = Array(keyStr.utf8)

        guard let plainBytes = aes128CBC(data: cipherBytes, key: keyBytes, encrypt: false),
              let jsonObj = try? JSONSerialization.jsonObject(with: Data(plainBytes)) as? [String: Any] else {
            return nil
        }

        let aesCsv = jsonObj["aesKeyStr"] as? String ?? ""
        let aesHex = aesCsv.split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16) }
            .map { String(format: "%02x", $0) }
            .joined()

        let lockKeyB64 = jsonObj["lockKey"] as? String ?? ""
        let unlockKeyStr = decryptCrc(lockKeyB64)
        let unlockKey = UInt32(unlockKeyStr) ?? 0

        let ver = jsonObj["lockVersion"] as? [String: Any]
        let pType = UInt8(ver?["protocolType"] as? Int ?? 5)
        let pVer = UInt8(ver?["protocolVersion"] as? Int ?? 3)
        let scene = UInt8(ver?["scene"] as? Int ?? 2)
        let lockName = (jsonObj["lockName"] as? String)?.isEmpty == false ? (jsonObj["lockName"] as! String) : customName

        guard aesHex.count == 32, unlockKey > 0 else { return nil }

        return SmartLock(
            name: lockName,
            macAddress: (jsonObj["lockMac"] as? String) ?? macStr,
            aesKeyHex: aesHex,
            unlockKey: unlockKey,
            adminPasscode: nil,
            protocolType: pType,
            protocolVersion: pVer,
            scene: scene
        )
    }

    private static func decryptCrc(_ b64: String) -> String {
        guard let data = Data(base64Encoded: b64),
              let csv = String(data: data, encoding: .ascii) else { return "" }
        let nums = csv.split(separator: ",").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count >= 2 else { return "" }
        let n = nums.count - 1
        let last = nums[n]
        let crcVal = crcTable[n % 256]
        var out: [UInt8] = []
        for i in 0..<n {
            out.append((nums[i] ^ last) ^ crcVal)
        }
        return String(bytes: out, encoding: .ascii) ?? ""
    }
}

import SwiftUI

struct AddLockView: View {
    @EnvironmentObject var store: LockStore
    @EnvironmentObject var ble: TTLockBLEManager
    @Environment(\.dismiss) var dismiss

    @State private var name = "房间门锁"
    @State private var macAddress = ""
    @State private var aesKeyHex = ""
    @State private var unlockKeyStr = ""
    @State private var protocolType = "5"
    @State private var protocolVersion = "3"
    @State private var scene = "2"
    @State private var lockDataInput = ""
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                    } label: {
                        HStack {
                            Label(ble.isScanning ? "停止扫描" : "扫描附近通通锁蓝牙", systemImage: "dot.radiowaves.left.and.right")
                            Spacer()
                            if ble.isScanning { ProgressView() }
                        }
                    }

                    ForEach(ble.discoveredLocks) { item in
                        Button {
                            macAddress = item.macAddress
                            protocolType = String(item.protocolType)
                            protocolVersion = String(item.protocolVersion)
                            scene = String(item.scene)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline.weight(.medium))
                                    Text(item.macAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("自动获取 MAC 地址")
                }

                Section {
                    TextField("粘贴 Base64 格式的 lockData", text: $lockDataInput, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.caption.monospaced())

                    Button("解析并自动填充下方参数") {
                        if let parsed = TTLockCrypto.parseLockDataBase64(lockDataInput, customName: name) {
                            macAddress = parsed.macAddress
                            aesKeyHex = parsed.aesKeyHex
                            unlockKeyStr = String(parsed.unlockKey)
                            protocolType = String(parsed.protocolType)
                            protocolVersion = String(parsed.protocolVersion)
                            scene = String(parsed.scene)
                            parseError = nil
                        } else {
                            parseError = "lockData 格式无效，请检查是否完整复制"
                        }
                    }
                    .disabled(lockDataInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let err = parseError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("快捷导入 (可选)")
                }

                Section {
                    TextField("门锁名称 (例如: 房间门锁)", text: $name)
                    TextField("Lock MAC address* (XX:XX:XX:XX:XX:XX)", text: $macAddress)
                        .textInputAutocapitalization(.characters)
                        .font(.body.monospaced())
                    TextField("AES key* (32位十六进制)", text: $aesKeyHex)
                        .textInputAutocapitalization(.never)
                        .font(.body.monospaced())
                    TextField("Unlock key* (纯数字)", text: $unlockKeyStr)
                        .keyboardType(.numberPad)
                        .font(.body.monospaced())
                } header: {
                    Text("核心鉴权参数")
                }

                Section {
                    HStack {
                        Text("Protocol type")
                        Spacer()
                        TextField("5", text: $protocolType).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Protocol version")
                        Spacer()
                        TextField("3", text: $protocolVersion).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Scene")
                        Spacer()
                        TextField("2", text: $scene).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("通信协议参数 (默认 V3 锁无需修改)")
                }
            }
            .navigationTitle("添加门锁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        ble.stopScan()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveLock()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onDisappear {
                ble.stopScan()
            }
        }
    }

    private var isValid: Bool {
        let cleanAes = aesKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return macAddress.count == 17 && cleanAes.count == 32 && UInt32(unlockKeyStr) != nil
    }

    private func saveLock() {
        guard let uKey = UInt32(unlockKeyStr) else { return }
        let newLock = SmartLock(
            name: name.isEmpty ? "智能门锁" : name,
            macAddress: macAddress.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
            aesKeyHex: aesKeyHex.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
            unlockKey: uKey,
            protocolType: UInt8(protocolType) ?? 5,
            protocolVersion: UInt8(protocolVersion) ?? 3,
            scene: UInt8(scene) ?? 2
        )
        store.add(newLock)
        dismiss()
    }
}
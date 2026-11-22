import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LockStore
    @EnvironmentObject var ble: TTLockBLEManager
    @State private var showAddSheet = false
    @State private var showManageSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                // iOS 26/27 液态环境背景光晕
                MeshAmbientBackground(isUnlocked: ble.lockState == .unlocked)
                    .ignoresSafeArea()

                if let lock = store.selectedLock {
                    ScrollView {
                        VStack(spacing: 24) {
                            // 顶部状态胶囊栏
                            statusHeader(for: lock)

                            // 核心液态玻璃圆形开锁交互盘
                            unlockDial(for: lock)
                                .padding(.vertical, 12)

                            // 快捷功能控制面板（闭锁 / 状态查询 / 校准时间）
                            quickActionsGrid(for: lock)

                            // 门锁底层参数摘要卡片
                            lockSpecCard(for: lock)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle(store.selectedLock?.name ?? "智能门锁")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.locks.count > 1 {
                        Menu {
                            ForEach(store.locks) { item in
                                Button {
                                    store.selectedLockId = item.id
                                } label: {
                                    Label(item.name, systemImage: item.id == store.selectedLock?.id ? "checkmark" : "lock")
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title3)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !store.locks.isEmpty {
                            Button {
                                showManageSheet = true
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                        }
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddLockView()
            }
            .sheet(isPresented: $showManageSheet) {
                ManageLocksView()
            }
        }
    }

    private func statusHeader(for lock: SmartLock) -> some View {
        LiquidGlassCard(cornerRadius: 20) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ble.isBusy ? Color.orange : (ble.lockState == .unlocked ? Color.green : Color.blue))
                        .frame(width: 8, height: 8)
                    Text(ble.statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if let bat = ble.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: bat > 20 ? "battery.75percent" : "battery.25percent")
                            .foregroundStyle(bat > 20 ? .green : .red)
                        Text("\(bat)%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func unlockDial(for lock: SmartLock) -> some View {
        Button {
            ble.execute(.unlock, on: lock)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 220, height: 220)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.8),
                                        .white.opacity(0.15),
                                        (ble.lockState == .unlocked ? Color.green : Color.blue).opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                    .shadow(color: (ble.lockState == .unlocked ? Color.green : Color.blue).opacity(0.22), radius: 30, y: 12)

                VStack(spacing: 12) {
                    if ble.isBusy {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: ble.lockState == .unlocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 54, weight: .medium))
                            .foregroundStyle(ble.lockState == .unlocked ? .green : .blue)
                            .contentTransition(.symbolEffect(.replace))
                    }

                    Text(ble.isBusy ? "通信中..." : "轻点开锁")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .disabled(ble.isBusy)
    }

    private func quickActionsGrid(for lock: SmartLock) -> some View {
        HStack(spacing: 14) {
            actionPill(title: "闭锁", icon: "lock.shield.fill", color: .indigo) {
                ble.execute(.lock, on: lock)
            }
            actionPill(title: "状态", icon: "sensor.tag.radiowaves.forward.fill", color: .teal) {
                ble.execute(.queryStatus, on: lock)
            }
            actionPill(title: "校时", icon: "clock.badge.checkmark.fill", color: .orange) {
                ble.execute(.syncTime, on: lock)
            }
        }
    }

    private func actionPill(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LiquidGlassCard(cornerRadius: 22) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .disabled(ble.isBusy)
    }

    private func lockSpecCard(for lock: SmartLock) -> some View {
        LiquidGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("设备信息")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                LabeledContent("MAC 地址", value: lock.macAddress)
                    .font(.subheadline.monospaced())
                Divider()
                LabeledContent("协议版本", value: "V\(lock.protocolVersion) (Type \(lock.protocolType) / Scene \(lock.scene))")
                    .font(.subheadline)
                Divider()
                LabeledContent("门锁状态", value: ble.lockState.rawValue)
                    .font(.subheadline)
            }
            .padding(18)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "door.left.hand.closed")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("尚未添加智能门锁")
                .font(.title3.weight(.semibold))
            Text("支持通过扫描附近蓝牙、手动输入密钥或粘贴抓包 lockData 添加")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAddSheet = true
            } label: {
                Text("添加门锁")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
        }
    }
}

struct MeshAmbientBackground: View {
    var isUnlocked: Bool

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            Circle()
                .fill((isUnlocked ? Color.green : Color.blue).opacity(0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -80, y: -180)
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 110, y: 140)
        }
    }
}

struct ManageLocksView: View {
    @EnvironmentObject var store: LockStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.locks) { lock in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lock.name).font(.headline)
                            Text(lock.macAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.selectedLock?.id == lock.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedLockId = lock.id
                        dismiss()
                    }
                }
                .onDelete(perform: store.delete)
            }
            .navigationTitle("管理门锁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
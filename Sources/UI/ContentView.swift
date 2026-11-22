import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LockStore
    @EnvironmentObject var ble: TTLockBLEManager
    @State private var showAddSheet = false
    @State private var showManageSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let lock = store.selectedLock {
                    lockControlList(for: lock)
                } else {
                    emptyStateView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let lock = store.selectedLock {
                        lockSwitcherMenu(currentLock: lock)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("添加门锁")
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

    // MARK: - 顶部原地展开的门锁切换菜单

    private func lockSwitcherMenu(currentLock: SmartLock) -> some View {
        Menu {
            Section("切换门锁") {
                ForEach(store.locks) { item in
                    Button {
                        store.selectedLockId = item.id
                    } label: {
                        if item.id == currentLock.id {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                }
            }

            Divider()

            Button {
                showManageSheet = true
            } label: {
                Label("管理门锁...", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Text(currentLock.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
            }
        }
    }

    // MARK: - 主界面原生分组列表

    private func lockControlList(for lock: SmartLock) -> some View {
        List {
            // 核心控制区
            Section {
                VStack(spacing: 20) {
                    // 状态图标与文案
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                                }

                            Image(systemName: lockSymbolName)
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(lockSymbolColor)
                                .contentTransition(.symbolEffect(.replace))
                        }

                        VStack(spacing: 4) {
                            Text(ble.lockState.rawValue)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(ble.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)

                    // 主开锁按钮（原生大号胶囊突出按钮）
                    Button {
                        ble.execute(.unlock, on: lock)
                    } label: {
                        HStack(spacing: 8) {
                            if ble.isBusy {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "lock.open.fill")
                            }
                            Text(ble.isBusy ? "正在通信..." : "轻点开锁")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(ble.isBusy)

                    // 次级操作组（原生 ControlGroup 分段玻璃栏）
                    ControlGroup {
                        Button {
                            ble.execute(.lock, on: lock)
                        } label: {
                            Label("闭锁", systemImage: "lock.fill")
                        }

                        Button {
                            ble.execute(.queryStatus, on: lock)
                        } label: {
                            Label("状态", systemImage: "arrow.clockwise")
                        }

                        Button {
                            ble.execute(.syncTime, on: lock)
                        } label: {
                            Label("校时", systemImage: "clock")
                        }
                    }
                    .controlSize(.large)
                    .disabled(ble.isBusy)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // 门锁实时状态
            Section("门锁状态") {
                LabeledContent("当前状态") {
                    Label(ble.lockState.rawValue, systemImage: lockSymbolName)
                        .foregroundStyle(lockSymbolColor)
                }

                LabeledContent("电池电量") {
                    if let bat = ble.batteryLevel {
                        Label("\(bat)%", systemImage: batterySymbol(for: bat))
                            .foregroundStyle(bat > 20 ? .green : .red)
                            .monospacedDigit()
                    } else {
                        Text("未读取")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("蓝牙通道") {
                    HStack(spacing: 6) {
                        if ble.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(ble.statusText)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 底层设备参数与管理入口
            Section("设备信息") {
                LabeledContent("MAC 地址") {
                    Text(lock.macAddress)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }

                LabeledContent("协议版本") {
                    Text("V\(lock.protocolVersion) · Type \(lock.protocolType) · Scene \(lock.scene)")
                        .foregroundStyle(.secondary)
                }

                Button {
                    showManageSheet = true
                } label: {
                    HStack {
                        Text("管理已保存门锁")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(store.locks.count) 把")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 原生空状态页面

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("尚未添加智能门锁", systemImage: "door.left.hand.closed")
        } description: {
            Text("点击右上角“+”扫描附近通通锁蓝牙，或粘贴抓包获取的 lockData 导入。")
        } actions: {
            Button("添加门锁") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    // MARK: - 状态图标辅助属性

    private var lockSymbolName: String {
        switch ble.lockState {
        case .unlocked: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .unknown: return "lock.shield"
        }
    }

    private var lockSymbolColor: Color {
        switch ble.lockState {
        case .unlocked: return .green
        case .locked: return .accentColor
        case .unknown: return .secondary
        }
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 80...100: return "battery.100percent"
        case 55..<80: return "battery.75percent"
        case 30..<55: return "battery.50percent"
        case 10..<30: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

// MARK: - 门锁管理列表

struct ManageLocksView: View {
    @EnvironmentObject var store: LockStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.locks) { lock in
                    Button {
                        store.selectedLockId = lock.id
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lock.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(lock.macAddress)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedLock?.id == lock.id {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .onDelete(perform: store.delete)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("管理门锁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
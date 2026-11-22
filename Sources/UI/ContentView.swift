import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LockStore
    @EnvironmentObject var ble: TTLockBLEManager
    @State private var showAddSheet = false
    @State private var showManageSheet = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

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
            // 四宫格卡片控制区（与下方分组卡片左右对齐）
            Section {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    actionTile(
                        title: "开锁",
                        subtitle: ble.isBusy ? "通信中..." : "蓝牙解锁",
                        systemImage: "lock.open.fill",
                        tint: .blue
                    ) {
                        ble.execute(.unlock, on: lock)
                    }

                    actionTile(
                        title: "闭锁",
                        subtitle: "立即上锁",
                        systemImage: "lock.fill",
                        tint: .indigo
                    ) {
                        ble.execute(.lock, on: lock)
                    }

                    actionTile(
                        title: "状态",
                        subtitle: "读取锁态与电量",
                        systemImage: "arrow.clockwise",
                        tint: .teal
                    ) {
                        ble.execute(.queryStatus, on: lock)
                    }

                    actionTile(
                        title: "校时",
                        subtitle: "同步手机时间",
                        systemImage: "clock.fill",
                        tint: .orange
                    ) {
                        ble.execute(.syncTime, on: lock)
                    }
                }
                .disabled(ble.isBusy)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            // 门锁状态（与设备信息保持完全一致的原生紧凑行高与分割线）
            Section("门锁状态") {
                LabeledContent("当前状态") {
                    Text(ble.lockState.rawValue)
                        .foregroundStyle(lockStateColor)
                }

                LabeledContent("电池电量") {
                    if let bat = ble.batteryLevel {
                        Text("\(bat)%")
                            .monospacedDigit()
                            .foregroundStyle(bat > 20 ? .green : .red)
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

            // 设备信息
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

    // MARK: - 原生 Apple Home 风格四宫格卡片按钮

    private func actionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.14), in: Circle())

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(LiquidGlassTileButtonStyle())
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

    private var lockStateColor: Color {
        switch ble.lockState {
        case .unlocked: return .green
        case .locked: return .primary
        case .unknown: return .secondary
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
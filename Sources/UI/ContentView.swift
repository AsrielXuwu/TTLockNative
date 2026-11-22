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
            .onAppear {
                if let lock = store.selectedLock, ble.lockState == .unknown, !ble.isBusy {
                    ble.syncLockState(for: lock, resetDisplay: true)
                }
            }
            .onChange(of: ble.isPoweredOn) { _, isOn in
                if isOn, !showAddSheet, let lock = store.selectedLock {
                    ble.syncLockState(for: lock, resetDisplay: false)
                }
            }
            .onChange(of: store.selectedLockId) { _, _ in
                if !showAddSheet, let lock = store.selectedLock {
                    ble.syncLockState(for: lock, resetDisplay: true)
                }
            }
        }
    }

    // MARK: - 顶部原生门锁切换菜单（iOS 26/27 自动渲染为系统液态玻璃胶囊）

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
            HStack(spacing: 4) {
                Text(currentLock.name)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
    }

    // MARK: - 主界面原生列表

    private func lockControlList(for lock: SmartLock) -> some View {
        List {
            // 顶部原生大锁图标状态展示
            Section {
                VStack(spacing: 12) {
                    Image(systemName: lockHeroSymbolName)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(lockStateColor)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 88, height: 88)
                        .nativeGlassCircle()

                    VStack(spacing: 4) {
                        Text(ble.lockState.rawValue)
                            .font(.title2.weight(.semibold))

                        HStack(spacing: 6) {
                            if ble.isBusy {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(ble.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            // 原生四宫格液态玻璃按钮
            Section {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    nativeActionTile(
                        title: "开锁",
                        systemImage: "lock.open.fill",
                        prominent: true
                    ) {
                        ble.execute(.unlock, on: lock)
                    }

                    nativeActionTile(
                        title: "闭锁",
                        systemImage: "lock.fill",
                        prominent: false
                    ) {
                        ble.execute(.lock, on: lock)
                    }

                    nativeActionTile(
                        title: "状态",
                        systemImage: "arrow.clockwise",
                        prominent: false
                    ) {
                        ble.execute(.queryStatus, on: lock)
                    }

                    nativeActionTile(
                        title: "校时",
                        systemImage: "clock",
                        prominent: false
                    ) {
                        ble.execute(.syncTime, on: lock)
                    }
                }
                .disabled(ble.isBusy)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            // 门锁状态
            Section("门锁状态") {
                LabeledContent("当前状态") {
                    Text(ble.lockState.rawValue)
                        .foregroundStyle(lockRowValueColor)
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

    // MARK: - 原生宫格按钮

    private func nativeActionTile(
        title: String,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .nativeGlassButton(prominent: prominent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
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
            .nativeGlassButton(prominent: true)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    private var lockHeroSymbolName: String {
        switch ble.lockState {
        case .unlocked: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .unknown: return "lock.shield.fill"
        }
    }

    private var lockStateColor: Color {
        switch ble.lockState {
        case .unlocked: return .green
        case .locked: return .accentColor
        case .unknown: return .secondary
        }
    }

    private var lockRowValueColor: Color {
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
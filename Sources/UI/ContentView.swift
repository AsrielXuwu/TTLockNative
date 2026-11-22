import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LockStore
    @EnvironmentObject var ble: TTLockBLEManager
    @State private var showAddSheet = false
    @State private var showManageSheet = false
    @State private var heroCollapseProgress: CGFloat = 0

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let lock = store.selectedLock {
                    lockControlView(for: lock)
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
                ToolbarItem(placement: .principal) {
                    if let lock = store.selectedLock {
                        let appear = min(max((heroCollapseProgress - 0.45) / 0.50, 0), 1)
                        Button {
                            let action: BLEAction = (ble.lockState == .unlocked) ? .lock : .unlock
                            ble.execute(action, on: lock)
                        } label: {
                            Image(systemName: lockHeroSymbolName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(lockStateColor)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 34, height: 34)
                        }
                        .nativeGlassButton(prominent: false)
                        .buttonBorderShape(.circle)
                        .disabled(ble.isBusy || appear < 0.2)
                        .scaleEffect(0.75 + 0.25 * appear)
                        .opacity(appear)
                        .accessibilityLabel(ble.lockState == .unlocked ? "闭锁" : "开锁")
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

    // MARK: - 顶部原生门锁切换菜单

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

    // MARK: - 主界面（无裁切滚动容器 + 原生分组卡片）

    private func lockControlView(for lock: SmartLock) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 顶部原生大锁图标状态展示（随页面上滑缩小并收入顶栏中央）
                VStack(spacing: 12) {
                    let heroFade = 1.0 - min(max((heroCollapseProgress - 0.45) / 0.50, 0), 1)
                    Button {
                        let action: BLEAction = (ble.lockState == .unlocked) ? .lock : .unlock
                        ble.execute(action, on: lock)
                    } label: {
                        Image(systemName: lockHeroSymbolName)
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(lockStateColor)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 72, height: 72)
                    }
                    .nativeGlassButton(prominent: false)
                    .buttonBorderShape(.circle)
                    .disabled(ble.isBusy || heroCollapseProgress > 0.5)
                    .scaleEffect(1.0 - 0.528 * heroCollapseProgress, anchor: .top)
                    .opacity(heroFade)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: HeroLockScrollOffsetKey.self,
                                value: geo.frame(in: .named("lockScroll")).minY
                            )
                        }
                    }
                    .accessibilityLabel(ble.lockState == .unlocked ? "闭锁" : "开锁")

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
                .padding(.top, 8)

                // 2. 四宫格原生液态玻璃按钮（独立渲染，无外层裁切）
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

                // 3 & 4. 门锁状态与设备信息（原生 Form，与添加门锁界面完全一致）
                Form {
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
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: 460)
                .padding(.horizontal, -20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .coordinateSpace(name: "lockScroll")
        .onPreferenceChange(HeroLockScrollOffsetKey.self) { minY in
            let progress = min(max((8.0 - minY) / 44.0, 0), 1)
            if abs(heroCollapseProgress - progress) > 0.005 {
                heroCollapseProgress = progress
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
        .buttonBorderShape(.roundedRectangle(radius: 26))
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

private struct HeroLockScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 8.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
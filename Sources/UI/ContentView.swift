import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LockStore
    @EnvironmentObject var ble: TTLockBLEManager
    @State private var showAddSheet = false
    @State private var showManageSheet = false

    // 滚动测量与顶栏收起动画状态（基于外层视口与内层内容的真实全局坐标差计算）
    @State private var containerTop: CGFloat? = nil
    @State private var contentTop: CGFloat? = nil
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
                // 1. 左侧门锁切换菜单：在未收起时显示，当大锁开始收起到顶栏时平滑淡出，避免与顶栏中央胶囊冲突
                ToolbarItem(placement: .topBarLeading) {
                    if let lock = store.selectedLock {
                        lockSwitcherMenu(currentLock: lock)
                            .opacity(max(1.0 - heroCollapseProgress * 2.5, 0))
                            .allowsHitTesting(heroCollapseProgress < 0.4)
                    }
                }

                // 2. 顶栏居中仿 iMessage 动态收起区域：大锁图标与门锁胶囊无缝渐入居中
                ToolbarItem(placement: .principal) {
                    if let lock = store.selectedLock {
                        VStack(spacing: 2) {
                            // 顶栏微型圆形锁按钮（仿 iMessage 头像位置）
                            Button {
                                let action: BLEAction = (ble.lockState == .unlocked) ? .lock : .unlock
                                ble.execute(action, on: lock)
                            } label: {
                                Image(systemName: lockHeroSymbolName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(lockStateColor)
                                    .contentTransition(.symbolEffect(.replace))
                                    .frame(width: 28, height: 28)
                            }
                            .nativeGlassButton(prominent: false)
                            .buttonBorderShape(.circle)
                            .disabled(ble.isBusy || heroCollapseProgress < 0.3)
                            .accessibilityLabel(ble.lockState == .unlocked ? "闭锁" : "开锁")

                            // 仿 iMessage 居中胶囊切换菜单
                            lockCapsuleMenu(currentLock: lock)
                        }
                        .scaleEffect(0.85 + 0.15 * heroCollapseProgress)
                        .offset(y: (1.0 - heroCollapseProgress) * 5)
                        .opacity(heroCollapseProgress)
                        .allowsHitTesting(heroCollapseProgress > 0.6)
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
                containerTop = nil
                contentTop = nil
                heroCollapseProgress = 0
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
                containerTop = nil
                contentTop = nil
                heroCollapseProgress = 0
                if !showAddSheet, let lock = store.selectedLock {
                    ble.syncLockState(for: lock, resetDisplay: true)
                }
            }
        }
    }

    // MARK: - 顶部原生门锁切换菜单（未收起时左侧常驻）

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

    // MARK: - 仿 iMessage 顶栏居中胶囊切换菜单

    private func lockCapsuleMenu(currentLock: SmartLock) -> some View {
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
            HStack(spacing: 3) {
                if ble.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(currentLock.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - 主界面（双探针无偏滚动测量 + 原生分组布局）

    private func lockControlView(for lock: SmartLock) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 顶部原生大锁图标与状态展示（滑动进入顶栏时平滑收起至顶栏中央，遵循 Apple 原生层级规范）
                VStack(spacing: 12) {
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
                    .disabled(ble.isBusy || heroCollapseProgress > 0.6)
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
                .scaleEffect(1.0 - 0.22 * heroCollapseProgress, anchor: .top)
                .opacity(1.0 - heroCollapseProgress)
                .allowsHitTesting(heroCollapseProgress < 0.6)

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

                // 3 & 4. 门锁状态与设备信息（原生 Form 呈现）
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
            // 内容绝对顶部探针：跟随内容滚动，有实体尺寸，SwiftUI 布局引擎每帧稳定派发更新
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollContentTopKey.self,
                        value: geo.frame(in: .global).minY
                    )
                }
            )
        }
        .scrollBounceBehavior(.always)
        // 视口容器绝对顶部探针：固定于 ScrollView 视口顶部，两者差值即为绝对精确的无偏滚动距离
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollContainerTopKey.self,
                    value: geo.frame(in: .global).minY
                )
            }
        )
        .onPreferenceChange(ScrollContainerTopKey.self) { value in
            containerTop = value
            updateScrollProgress()
        }
        .onPreferenceChange(ScrollContentTopKey.self) { value in
            contentTop = value
            updateScrollProgress()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - 滚动进度精确计算

    private func updateScrollProgress() {
        guard let container = containerTop, let content = contentTop else { return }
        let scrollDistance = max(0, container - content)
        // 门锁大图标进入顶栏范围开始收起（约 8pt），滑动约 74pt 完成完全收起至顶栏
        let startOffset: CGFloat = 8.0
        let endOffset: CGFloat = 82.0
        let progress = min(max((scrollDistance - startOffset) / (endOffset - startOffset), 0), 1.0)
        if abs(heroCollapseProgress - progress) > 0.002 {
            heroCollapseProgress = progress
        }
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

// MARK: - 滚动位置 Preference Keys

private struct ScrollContainerTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollContentTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

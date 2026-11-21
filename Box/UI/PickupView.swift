import SwiftUI

struct PickupView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject private var session = PlatformSession.shared
    @State private var detail: Parcel? = nil
    @State private var showAdd = false
    @State private var identity: IdentityKind? = nil
    @State private var syncing = false
    @State private var showTrack = false

    private var accent: Color { Palette.accent(store.settings.accentName) }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                Palette.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if !identityKinds.isEmpty { identityRow }
                        pendingSection
                        transitSection
                        pickedSection
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 116)
                }
                .refreshable { await refresh() }
            }
            .navigationTitle("取件")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.tap()
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .tint(accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if syncing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .tint(accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("智能识别文本", systemImage: "text.viewfinder") { showAdd = true }
                        Button("运单号查单", systemImage: "magnifyingglass") { showTrack = true }
                        if store.settings.simpleMode {
                            Divider()
                            Button("退出简洁模式", systemImage: "rectangle.expand.vertical") {
                                store.settings.simpleMode = false
                                store.save()
                                store.toast = "已恢复四个标签页"
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .tint(accent)
                }
            }
            .sheet(item: $detail) { p in
                ParcelDetailView(parcelID: p.id)
            }
            .sheet(isPresented: $showAdd) {
                AddParcelSheet()
            }
            .sheet(isPresented: $showTrack) { TrackSearchSheet() }
            .sheet(item: $identity) { kind in
                IdentitySheet(kind: kind)
            }
            .overlay(alignment: .bottom) {
                if let toast = store.toast {
                    ToastView(text: toast)
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            if !Task.isCancelled { withAnimation { store.toast = nil } }
                        }
                }
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting + (store.settings.nickName.isEmpty ? "" : "，\(store.settings.nickName)"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(store.pending.count)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Text("件待取")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                if let last = store.lastSync {
                    Text("同步于 \(Fmt.relative(last))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
            }

            HStack(spacing: 0) {
                metric("本月取件", "\(store.stats.pickedThisMonth)")
                divider
                metric("累计快件", "\(store.stats.total)")
                divider
                metric("最常驿站", store.stats.topStation.isEmpty ? "—" : store.stats.topStation.replacingOccurrences(of: "菜鸟驿站·", with: ""))
            }
            .padding(.vertical, 12)
            .cardStyle()
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.separator).frame(width: 0.6, height: 26)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 身份码

    /// 只对已授权的平台显示身份码入口（没授权时码是假的，不该出现）
    private var identityKinds: [IdentityKind] {
        IdentityKind.allCases.filter { kind in
            switch kind {
            case .taobao: return session.isAuthorized(.taobao)
            case .cainiao: return session.isAuthorized(.cainiao)
            }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 10) {
            ForEach(identityKinds) { kind in
                Button {
                    Haptic.tap()
                    identity = kind
                } label: {
                    HStack(spacing: 7) {
                        Image(kind.asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Text("向平台获取")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .cardStyle(radius: 14, fill: Palette.card2)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: 待取

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("待取").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if !store.pending.isEmpty {
                    Text("\(store.pending.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.field))
                }
            }

            if store.pending.isEmpty {
                EmptyBox(icon: "shippingbox", title: "没有待取的包裹", subtitle: "到站后会出现在这里，也可以手动添加")
                    .cardStyle()
            } else {
                ForEach(store.groupByStation(), id: \.name) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: group.name == "其他驿站" ? "mappin.slash" : "mappin.and.ellipse")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accent)
                            Text(group.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.secondary)
                            Text("\(group.parcels.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.tertiary)
                        }
                        .padding(.leading, 4)

                        ForEach(group.parcels) { p in
                            ParcelCard(parcel: p) {
                                withAnimation(.easeInOut) { store.markPicked(p.id) }
                                store.toast = "已标记「\(p.title)」已取"
                            }
                            .onTapGesture { detail = p }
                            .contextMenu {
                                Button("标记已取", systemImage: "checkmark.circle") {
                                    withAnimation { store.markPicked(p.id) }
                                }
                                Button("查看详情", systemImage: "info.circle") { detail = p }
                                Divider()
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    withAnimation { store.delete(p.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 在途

    @ViewBuilder
    private var transitSection: some View {
        if !store.transit.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                    Text("在途").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text("\(store.transit.count)").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                .padding(.leading, 4)

                ForEach(store.transit.prefix(3)) { p in
                    ParcelCard(parcel: p, compact: true)
                        .onTapGesture { detail = p }
                }
            }
        }
    }

    // MARK: 已取

    @ViewBuilder
    private var pickedSection: some View {
        if !store.pickedRecent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.green)
                    Text("最近已取").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                }
                .padding(.leading, 4)

                ForEach(store.pickedRecent.prefix(2)) { p in
                    ParcelCard(parcel: p, compact: true)
                        .onTapGesture { detail = p }
                }
            }
        }
    }

    private var footerNote: some View {
        Text("数据只存在本机，不上传服务器")
            .font(.system(size: 11))
            .foregroundStyle(Palette.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    // MARK: 动作

    @MainActor
    private func refresh() async {
        // 下拉 + 工具栏按钮可能同时触发，重复请求会互相取消（URLError -999）
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }

        let report = await SyncService.shared.syncAll(store: store)
        // 视图被销毁/切页导致的取消不算失败，不弹任何提示
        guard !report.isEmpty, !Task.isCancelled else { return }
        store.toast = report
    }
}

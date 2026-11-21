import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @State private var showAbout = false
    @State private var showNickname = false
    @State private var nickDraft = ""
    @State private var notifAuthorized = false
    @State private var notifStatus = "未询问"
    @State private var syncing = false
    @State private var clearResult: String? = nil
    @State private var showTrack = false
    @State private var askClear = false
    @ObservedObject private var accountStore = AccountStore.shared

    private var accent: Color { Palette.accent(store.settings.accentName) }

    private var authorizedCount: Int {
        Platform.allCases.filter { PlatformSession.shared.isAuthorized($0) }.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            profileCard
                            platformCard
                            reminderCard
                            appearanceCard
                            dataCard
                            aboutCard
                                .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 116)
                    }
                    .onAppear {
                        if ProcessInfo.processInfo.arguments.contains("-bottom") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showAbout) { AboutSheet() }
            .sheet(isPresented: $showTrack) { TrackSearchSheet() }
            .alert("清空所有包裹？", isPresented: $askClear) {
                Button("清空", role: .destructive) { store.clearAllData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("包裹、驿站、身份码都会删除，设置与授权保留。")
            }
            .alert("你的昵称", isPresented: $showNickname) {
                TextField("昵称", text: $nickDraft)
                Button("保存") {
                    store.settings.nickName = nickDraft.trimmingCharacters(in: .whitespaces)
                    store.save()
                }
                Button("取消", role: .cancel) {}
            }
            .task {
                await Notifier.shared.refreshAuthorization()
                notifAuthorized = await Notifier.shared.authorized
                notifStatus = await Notifier.shared.statusText
            }
            .overlay(alignment: .bottom) {
                if let toast = store.toast {
                    ToastView(text: toast)
                        .padding(.bottom, 26)
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            if !Task.isCancelled { withAnimation { store.toast = nil } }
                        }
                }
            }
        }
    }

    // MARK: 账号

    private var profileCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.16))
                Text(store.settings.nickName.isEmpty ? "📦" : String(store.settings.nickName.prefix(1)))
                    .font(.system(size: 24))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.settings.nickName.isEmpty ? "未设置昵称" : store.settings.nickName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(store.parcels.count) 个包裹 · \(authorizedCount)/\(Platform.allCases.count) 个平台 · \(accountStore.accounts.count) 个账号")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiary)
            }
            Spacer()
            Button {
                nickDraft = store.settings.nickName
                showNickname = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Palette.field))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: 平台

    private var platformCard: some View {
        SectionCard(title: "平台授权", caption: "登录态只存本机钥匙串；未授权的平台不联网。") {
            NavigationLink(destination: PlatformAuthView()) {
                RowLink(icon: "link", iconColor: accent, title: "授权管理", subtitle: "\(authorizedCount) 个平台已连接") {
                    HStack(spacing: 4) {
                        Text("管理").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            DividerLine()
            HStack(spacing: 6) {
                ForEach(Platform.allCases) { p in
                    Image(p.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                        .opacity(PlatformSession.shared.isAuthorized(p) ? 1 : 0.32)
                }
                Spacer()
                Text("已连接 \(authorizedCount)/\(Platform.allCases.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.top, 10)
        }
    }

    // MARK: 提醒

    private var reminderCard: some View {
        SectionCard(title: "取件提醒") {
            toggleRow(icon: "bell.badge", title: "到站提醒", subtitle: "包裹到站后按提醒时刻推送", isOn: Binding(
                get: { store.settings.reminderEnabled },
                set: { v in
                    store.settings.reminderEnabled = v
                    store.save()
                    if v { Task { _ = await Notifier.shared.requestPermission() } }
                    Notifier.shared.refresh(parcels: store.parcels, settings: store.settings)
                }
            ))
            DividerLine()
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 26)
                Text("提醒时刻").font(.system(size: 15)).foregroundStyle(Palette.text)
                Spacer()
                Picker("", selection: Binding(
                    get: { store.settings.reminderHour },
                    set: { v in
                        store.settings.reminderHour = v
                        store.save()
                        Notifier.shared.refresh(parcels: store.parcels, settings: store.settings)
                    }
                )) {
                    ForEach(Array(stride(from: 6, through: 23, by: 1)), id: \.self) { h in
                        Text(String(format: "%02d:00", h)).tag(h)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.secondary)
            }
            .padding(.vertical, 9)
            DividerLine()
            Button {
                Task {
                    let granted = await Notifier.shared.requestPermission()
                    notifAuthorized = granted
                    notifStatus = await Notifier.shared.statusText
                    if granted {
                        Notifier.shared.test { err in
                            store.toast = err == nil ? "已发送，3 秒后弹横幅（前台也会显示）" : "排程失败：\(err!.localizedDescription)"
                        }
                    } else {
                        let st = await Notifier.shared.statusText
                        store.toast = "通知权限：\(st)"
                        if st == "已被拒绝", let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                }
            } label: {
                RowLink(icon: "bell.badge", iconColor: Palette.orange,
                        title: "发一条测试通知",
                        subtitle: notifAuthorized ? "已允许 · 点一下立刻发一条" : "权限：\(notifStatus)") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundStyle(Palette.text)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.tertiary) }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(accent)
        }
        .padding(.vertical, 8)
    }

    // MARK: 外观

    private var appearanceCard: some View {
        SectionCard(title: "外观") {
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 26)
                Text("模式").font(.system(size: 15)).foregroundStyle(Palette.text)
                Spacer()
                Picker("", selection: Binding(
                    get: { store.settings.appearance },
                    set: { store.settings.appearance = $0; store.save() }
                )) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            .padding(.vertical, 6)

            DividerLine()

            VStack(alignment: .leading, spacing: 9) {
                Text("主题色").font(.system(size: 15)).foregroundStyle(Palette.text)
                HStack(spacing: 12) {
                    ForEach(Palette.accents, id: \.name) { item in
                        Button {
                            Haptic.tap()
                            store.settings.accentName = item.name
                            store.save()
                        } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: item.hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Palette.text.opacity(0.9), lineWidth: store.settings.accentName == item.name ? 2 : 0)
                                            .padding(-4)
                                    )
                                Text(item.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(store.settings.accentName == item.name ? Palette.text : Palette.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .padding(.vertical, 8)

            DividerLine()
            toggleRow(icon: "rectangle.compress.vertical", title: "简洁模式", subtitle: "只保留取件页；退出在取件页右上角 ⋯ 菜单", isOn: Binding(
                get: { store.settings.simpleMode },
                set: { v in
                    store.settings.simpleMode = v
                    store.save()
                    if v { store.toast = "简洁模式已打开，退出在取件页右上角 ⋯" }
                }
            ))
        }
    }

    // MARK: 数据

    private var dataCard: some View {
        SectionCard(title: "数据") {
            Button { showTrack = true } label: {
                RowLink(icon: "magnifyingglass", iconColor: Palette.blue,
                        title: "运单号查单", subtitle: KdniaoService.shared.isLoggedIn ? "快递鸟 8001 即时查询" : "先去授权页填快递鸟 AppKey") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)

            DividerLine()

            Button {
                Task {
                    syncing = true
                    let msg = await SyncService.shared.syncAll(store: store)
                    syncing = false
                    if !msg.isEmpty { store.toast = msg }
                }
            } label: {
                RowLink(icon: "arrow.triangle.2.circlepath", iconColor: accent,
                        title: "立即同步", subtitle: syncing ? "同步中…" : "按已授权平台拉取订单") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)

            DividerLine()

            Button {
                let n = store.clearHistory()
                clearResult = n > 0 ? "已清除 \(n) 条 30 天前的历史" : "没有可清除的历史"
                store.toast = clearResult
            } label: {
                RowLink(icon: "clock.arrow.circlepath", iconColor: Palette.orange,
                        title: "清除历史", subtitle: "删除已取超过 30 天的包裹") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)

            DividerLine()

            Button { askClear = true } label: {
                RowLink(icon: "trash", iconColor: Palette.red,
                        title: "清空包裹数据", subtitle: "保留设置与平台授权") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)


        }
    }

    // MARK: 关于

    private var aboutCard: some View {
        SectionCard(title: "关于") {
            Button { showAbout = true } label: {
                RowLink(icon: "info.circle", title: "关于包裹助手", subtitle: "原生重制版 v1.2.0") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)
            DividerLine()
            Button {
                Haptic.tap()
                if let url = URL(string: "https://t.me/gyddpu") { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            } label: {
                RowLink(icon: "paperplane.fill", iconColor: Color(hex: "#229ED9"),
                        title: "加入我们的频道", subtitle: "t.me/gyddpu") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .buttonStyle(.plain)
            DividerLine()
            HStack {
                Text("来源").font(.system(size: 15)).foregroundStyle(Palette.text)
                Spacer()
                Text("Scripting 版「包裹助手」1.2.0").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            .padding(.vertical, 11)
        }
    }
}

// MARK: - 关于页

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: "#8E5AC8"), Color(hex: "#3A226E")],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("包裹助手").font(.system(size: 20, weight: .semibold))
                            Text("v1.2.0 · 原生 SwiftUI 重制").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                            Text("开发者：豆姐（豆包）").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                    }

                    channelCard

                    text("把 Scripting 版「包裹助手」的界面与本地逻辑搬到原生 SwiftUI：识别短信/截图文字、取件码核算、驿站分组、统计、身份码，都是本机计算。")

                    section("已移植", [
                        "短信 / 文本智能识别（正则与评分规则原样搬运）",
                        "取件码卡片、驿站分组、已取标记与统计口径",
                        "身份码展示（Code128 条码 + 倒计时）",
                        "本地通知提醒、主题色与深浅色",
                    ])

                    section("原生新增", [
                        "平台登录用 WKWebView 真授权，Cookie 存钥匙串",
                        "淘宝 / 菜鸟 走 MTOP 接口拉包裹清单",
                        "Swipe / 长按菜单 / 触感反馈等系统交互",
                    ])

                    section("隐私", [
                        "数据只写沙盒里的 Application Support，不上传。",
                        "未授权的平台不会发起任何网络请求。",

                    ])

                    Text("本软件完全由豆姐（豆包）开发，本人未参与任何开发或操作。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)

                    Text("根据他人分享的 Scripting 脚本「包裹助手.scripting」改写为原生版本。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
                .padding(20)
            }
            .background(Palette.bg)
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private var channelCard: some View {
        Button {
            openChannel()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#37AEE2"), Color(hex: "#1E96C8")],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("加入我们的频道")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text("t.me/gyddpu · 更新与使用技巧")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(radius: 16)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("复制频道链接", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "https://t.me/gyddpu"
                Haptic.tap()
            }
        }
    }

    private func openChannel() {
        Haptic.tap()
        guard let app = URL(string: "tg://resolve?domain=gyddpu") else { return }
        let web = URL(string: "https://t.me/gyddpu")!
        UIApplication.shared.open(app, options: [:]) { ok in
            if !ok { UIApplication.shared.open(web) }
        }
    }

    private func text(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(Palette.secondary)
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Palette.tertiary).frame(width: 4, height: 4).padding(.top, 6)
                    Text(item).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

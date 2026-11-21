import SwiftUI
import WebKit

// MARK: - WKWebView 登录容器

struct WebLoginView: UIViewRepresentable {
    let url: URL
    let userAgent: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        if let userAgent { web.customUserAgent = userAgent }
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Cookie 类平台登录（淘宝 / 菜鸟 / 京东 / 拼多多）

struct PlatformLoginSheet: View {
    let platform: Platform
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var message: String? = nil

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                if let url = platform.loginURL {
                    WebLoginView(url: url, userAgent: ua)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    EmptyBox(icon: "exclamationmark.triangle", title: "暂无登录页", subtitle: "该平台需要单独接入")
                }

                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.red.opacity(0.92)))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("登录\(platform.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        harvest()
                    } label: {
                        if loading { ProgressView() } else { Text("完成").bold() }
                    }
                    .disabled(loading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("登录成功后点右上角「完成」，只保存该平台域名的 Cookie")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private func harvest() {
        loading = true
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let mine = cookies.filter { c in
                platform.cookieDomains.contains { c.domain.hasSuffix($0) || c.domain.hasSuffix("." + $0) }
            }
            let hasSession = mine.contains { c in
                platform.sessionCookies.contains(c.name) && !c.value.isEmpty
            }
            DispatchQueue.main.async {
                loading = false
                if hasSession {
                    PlatformSession.shared.save(mine, for: platform)
                    if platform == .taobao { PlatformSession.shared.refreshAll() }
                    Haptic.success()
                    dismiss()
                } else {
                    Haptic.warn()
                    withAnimation {
                        message = mine.isEmpty ? "没拿到 Cookie，登录可能没完成" : "还没有真正的登录凭证，请重新登录"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { message = nil }
                    }
                }
            }
        }
    }
}

// MARK: - 授权管理

struct PlatformAuthView: View {
    @ObservedObject var store = Store.shared

    enum Route: Identifiable {
        case login(Platform), harvest(Platform), fengchao, xiaomi, kdniao, track
        var id: String {
            switch self {
            case .login(let p): return "login-\(p.rawValue)"
            case .harvest(let p): return "harvest-\(p.rawValue)"
            case .fengchao: return "fengchao"
            case .xiaomi: return "xiaomi"
            case .kdniao: return "kdniao"
            case .track: return "track"
            }
        }
    }

    @State private var route: Route? = nil
    @State private var managing: Platform? = nil
    @ObservedObject private var accountStore = AccountStore.shared
    @State private var busy: Platform? = nil
    @State private var syncingAll = false

    private var accent: Color { Palette.accent(store.settings.accentName) }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard(title: "平台", caption: "Cookie 与令牌只存本机钥匙串；解除授权会一并清掉。") {
                        ForEach(Array(Platform.allCases.enumerated()), id: \.element) { idx, p in
                            row(p)
                            if idx < Platform.allCases.count - 1 { DividerLine() }
                        }
                    }

                    SectionCard(title: "全部同步") {
                        Button {
                            Task {
                                syncingAll = true
                                let msg = await SyncService.shared.syncAll(store: store)
                                syncingAll = false
                                if !msg.isEmpty { store.toast = msg }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if syncingAll { ProgressView().scaleEffect(0.8) }
                                Text(syncingAll ? "同步中…" : "立即同步所有平台")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(accent)
                                Spacer()
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                    }

                    SectionCard(title: "各平台怎么走") {
                        VStack(alignment: .leading, spacing: 9) {
                            explain("淘宝 / 菜鸟", "MTOP 网关，Cookie 换 token 拉包裹清单（已实现）")
                            explain("京东", "网页登录后进「我的 → 全部订单」，解析订单卡片（已实现）")
                            explain("拼多多", "网页登录后拉订单页，解析 order_sn 卡片（已实现）")
                            explain("丰巢", "手机号 + 短信，RSA 签名换 token，查在柜件与取件码（已实现）")
                            explain("小米", "扫码登录 → serviceLogin 换 serviceToken → AES 加密接口（已实现）")
                            explain("快递鸟", "填 EBusinessID + AppKey，8001 即时查询兜底（已实现）")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("平台授权")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $route) { r in
            switch r {
            case .login(let p): PlatformLoginSheet(platform: p)
            case .harvest(let p): HarvestSheet(platform: p)
            case .fengchao: FengchaoLoginSheet()
            case .xiaomi: XiaomiLoginSheet()
            case .kdniao: KdniaoCredentialSheet()
            case .track: TrackSearchSheet()
            }
        }
        .confirmationDialog(managing.map { "\($0.title)账号" } ?? "", isPresented: Binding(
            get: { managing != nil },
            set: { if !$0 { managing = nil } }
        ), titleVisibility: .visible) {
            if let p = managing {
                let list = accountStore.accounts(p)
                let current = accountStore.active(p)?.id
                ForEach(list) { acc in
                    Button(acc.id == current ? "✓ \(acc.label)" : "切换到 \(acc.label)") {
                        accountStore.switchTo(acc.id, p)
                        managing = nil
                    }
                }
                Button("添加账号") { route = loginRoute(p); managing = nil }
                Button("同步") { sync(p); managing = nil }
                if let cur = accountStore.active(p) {
                    Button("移除当前账号", role: .destructive) {
                        accountStore.remove(cur.id, p)
                        managing = nil
                    }
                }
            }
            Button("取消", role: .cancel) { managing = nil }
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

    private func authorized(_ p: Platform) -> Bool {
        if p == .cainiao { return PlatformSession.shared.isAuthorized(.taobao) }
        return PlatformSession.shared.isAuthorized(p)
    }

    private func row(_ p: Platform) -> some View {
        HStack(spacing: 12) {
            Image(p.asset)
                .resizable().scaledToFit().frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .opacity(authorized(p) ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
                    if authorized(p) { StatusPill(text: "已连接", color: Palette.green) }
                }
                Text(p.note).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
                if authorized(p), let acc = accountStore.effective(p) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                        Text(acc.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                        let n = accountStore.count(p)
                        if n > 1 {
                            Text("· 共 \(n) 个账号")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                if authorized(p) {
                    Button {
                        Haptic.tap()
                        sync(p)
                    } label: {
                        Text(busy == p ? "同步中" : "同步")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                }
                if p != .cainiao {
                Button {
                    Haptic.tap()
                    open(p)
                } label: {
                    Text(authorized(p) ? "管理" : "登录")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(authorized(p) ? Palette.secondary : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(authorized(p) ? Palette.field : accent))
                }
                .buttonStyle(.plain)
                } else if !authorized(p) {
                    Button {
                        Haptic.tap()
                        route = .login(.taobao)
                    } label: {
                        Text("登录淘宝")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if authorized(p) {
                Button("解除授权", systemImage: "xmark.circle", role: .destructive) {
                    PlatformSession.shared.clear(p)
                }
            }
        }
    }

    private func open(_ p: Platform) {
        if p == .cainiao {
            // 菜鸟没有独立登录：没登录淘宝就先去登淘宝
            if !PlatformSession.shared.isAuthorized(.taobao) { route = .login(.taobao) }
            return
        }
        guard !authorized(p) else { managing = p; return }
        switch p {
        case .taobao, .cainiao, .jd, .pdd: route = .login(p)
        case .fengchao: route = .fengchao
        case .mi: route = .xiaomi
        case .kdniao: route = .kdniao
        }
    }

    private func loginRoute(_ p: Platform) -> Route {
        switch p {
        case .taobao, .cainiao, .jd, .pdd: return .login(p)
        case .fengchao: return .fengchao
        case .mi: return .xiaomi
        case .kdniao: return .kdniao
        }
    }

    private func sync(_ p: Platform) {
        switch p {
        case .jd, .pdd:
            route = .harvest(p)
        case .taobao, .cainiao, .fengchao, .mi:
            Task {
                busy = p
                let msg: String
                switch p {
                case .fengchao: msg = await SyncService.shared.syncFengchao(store: store)
                case .mi: msg = await SyncService.shared.syncXiaomi(store: store)
                default: msg = await SyncService.shared.syncAll(store: store)
                }
                busy = nil
                if !msg.isEmpty { store.toast = msg }
            }
        case .kdniao:
            route = .track
        }
    }

    private func explain(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(accent.opacity(0.7)).frame(width: 5, height: 5).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                Text(text).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
        }
    }
}

import SwiftUI
import WebKit

// MARK: - 丰巢：手机号 + 短信验证码

struct FengchaoLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var sending = false
    @State private var logging = false
    @State private var countdown = 0
    @State private var message: String? = nil
    @State private var ok = false

    private let service = FengchaoService.shared

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        SectionCard(title: "丰巢账号", caption: "登录态存钥匙串；验证码由丰巢短信下发，纯原生请求，不走网页。") {
                            HStack(spacing: 10) {
                                Text("手机号").font(.system(size: 14)).foregroundStyle(Palette.text)
                                TextField("11 位手机号", text: $phone)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15, design: .rounded))
                            }
                            .padding(.vertical, 10)
                            DividerLine()
                            HStack(spacing: 10) {
                                Text("验证码").font(.system(size: 14)).foregroundStyle(Palette.text)
                                TextField("短信验证码", text: $code)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15, design: .rounded))
                                Button {
                                    Task { await send() }
                                } label: {
                                    Text(sending ? "发送中" : (countdown > 0 ? "\(countdown)s" : "获取验证码"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(countdown > 0 ? Palette.tertiary : Palette.accent(Store.shared.settings.accentName))
                                }
                                .disabled(sending || countdown > 0 || phone.count < 11)
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 10)
                        }

                        if let message {
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(ok ? Palette.green : Palette.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }

                        Button {
                            Task { await login() }
                        } label: {
                            HStack {
                                if logging { ProgressView().tint(.white) }
                                Text(logging ? "登录中…" : "登录丰巢")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Palette.accent(Store.shared.settings.accentName)))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(logging || phone.count < 11 || code.count < 4)

                        Text("协议：secureCheckMobile → RSA(PKCS1v15) 签名 → secureSendCode → secureLoginByPhone，与脚本版 utils/fengchao.ts 一致。")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 6)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("登录丰巢")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
        }
    }

    private func send() async {
        sending = true
        message = nil
        defer { sending = false }
        do {
            try await service.sendCode(phone)
            ok = true
            message = "验证码已发送"
            countdown = 60
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
        } catch {
            ok = false
            message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func login() async {
        logging = true
        message = nil
        defer { logging = false }
        do {
            try await service.login(mobile: phone, code: code)
            ok = true
            message = "登录成功"
            Haptic.success()
            dismiss()
        } catch {
            ok = false
            message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 小米：扫码登录 + 绑定手机号

struct XiaomiLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phonesText = ""
    @State private var minting = false
    @State private var message: String? = nil
    @State private var ok = false
    @State private var web: WKWebView? = nil

    private let service = XiaomiService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let web {
                    RunnerWebView(web: web)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }

                VStack(spacing: 10) {
                    if let message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(ok ? Palette.green : Palette.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Text("手机号").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        TextField("绑定的手机号，逗号分隔", text: $phonesText)
                            .font(.system(size: 13))
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.field))

                    HStack(spacing: 10) {
                        Button {
                            Task { await finishLogin() }
                        } label: {
                            HStack {
                                if minting { ProgressView().tint(.white) }
                                Text(minting ? "换取令牌…" : "完成登录")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Palette.accent(Store.shared.settings.accentName)))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(minting)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("登录小米账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
        }
        .task {
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .default()
            let w = WKWebView(frame: .zero, configuration: cfg)
            w.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
            if let url = Platform.mi.loginURL { w.load(URLRequest(url: url)) }
            web = w
            phonesText = service.phones.joined(separator: ",")
        }
    }

    private func finishLogin() async {
        minting = true
        message = nil
        defer { minting = false }
        let phones = phonesText.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { $0.filter(\.isNumber) }.filter { $0.count == 11 }
        service.phones = phones

        let cookies = await allCookies()
        guard service.saveLogin(cookies: cookies) else {
            ok = false
            message = "没拿到小米登录态（userId/passToken），请先完成网页登录"
            return
        }
        do {
            _ = try await service.mintToken()
            let n = try await service.fetchList().count
            ok = true
            message = "登录成功，小米快递里有 \(n) 条"
            Haptic.success()
            PlatformSession.shared.refreshAll()
            if n >= 0 { dismiss() }
        } catch {
            ok = false
            message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { list in
                cont.resume(returning: list.filter { $0.domain.hasSuffix("xiaomi.com") })
            }
        }
    }
}

// MARK: - 快递鸟：AppKey 填单页

struct KdniaoCredentialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ebid = ""
    @State private var appKey = ""
    @State private var message: String? = nil
    @State private var ok = false

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        SectionCard(title: "接口密钥", caption: "在 biz.kdniao.com → 快递鸟集成 → API 密钥里能看到。只存钥匙串。") {
                            HStack {
                                Text("EBusinessID").font(.system(size: 14)).foregroundStyle(Palette.text).frame(width: 110, alignment: .leading)
                                TextField("用户 ID", text: $ebid)
                                    .font(.system(size: 14, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(.vertical, 10)
                            DividerLine()
                            HStack {
                                Text("AppKey").font(.system(size: 14)).foregroundStyle(Palette.text).frame(width: 110, alignment: .leading)
                                TextField("接口密钥", text: $appKey)
                                    .font(.system(size: 14, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(.vertical, 10)
                        }

                        if let message {
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(ok ? Palette.green : Palette.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }

                        Button {
                            save()
                        } label: {
                            Text("保存")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14)
                                    .fill(Palette.accent(Store.shared.settings.accentName)))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(ebid.isEmpty || appKey.isEmpty)

                        if KdniaoService.shared.isLoggedIn {
                            Button(role: .destructive) {
                                KdniaoService.shared.clear()
                                dismiss()
                            } label: {
                                Text("解除快递鸟授权")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.red)
                            }
                        }

                        Text("签名：DataSign = base64(md5(RequestData + AppKey))，请求类型 8001 即时查询；没授权菜鸟时先用快递100 识别单号。")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 6)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("快递鸟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .task {
                if let c = KdniaoService.shared.credential {
                    ebid = c.eBusinessId
                    appKey = c.appKey
                }
            }
        }
    }

    private func save() {
        KdniaoService.shared.save(KdCredential(eBusinessId: ebid.trimmingCharacters(in: .whitespaces),
                                               appKey: appKey.trimmingCharacters(in: .whitespaces)))
        ok = true
        message = "已保存，可以去查单了"
        Haptic.success()
    }
}

// MARK: - 运单号查询

struct TrackSearchSheet: View {
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    @State private var mailNo = ""
    @State private var phone = ""
    @State private var loading = false
    @State private var track: KdTrack? = nil
    @State private var error: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        SectionCard(title: "运单号查询", caption: "优先走快递鸟 8001；没填密钥时只做单号识别。") {
                            HStack(spacing: 10) {
                                TextField("运单号", text: $mailNo)
                                    .font(.system(size: 15, design: .monospaced))
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                if !mailNo.isEmpty {
                                    Button { mailNo = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 10)
                            DividerLine()
                            HStack(spacing: 10) {
                                TextField("收件人手机后四位（中通/顺丰/京东需要）", text: $phone)
                                    .font(.system(size: 13))
                                    .keyboardType(.numberPad)
                            }
                            .padding(.vertical, 10)
                        }

                        Button {
                            Task { await search() }
                        } label: {
                            HStack {
                                if loading { ProgressView().tint(.white) }
                                Text(loading ? "查询中…" : "查询")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent(store.settings.accentName)))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(loading || mailNo.count < 6)

                        if let error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }

                        if let track {
                            SectionCard(title: "\(track.company) · \(track.mailNo)") {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let code = track.pickupCode {
                                        HStack(spacing: 6) {
                                            Text("取件码").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                            CodeText(text: code, size: 20)
                                        }
                                    }
                                    ForEach(Array(track.nodes.enumerated()), id: \.offset) { idx, node in
                                        HStack(alignment: .top, spacing: 9) {
                                            Circle()
                                                .fill(idx == 0 ? Palette.accent(store.settings.accentName) : Palette.tertiary.opacity(0.5))
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 5)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(node.text).font(.system(size: 13)).foregroundStyle(idx == 0 ? Palette.text : Palette.secondary)
                                                Text(node.time).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    Button {
                                        addParcel(track)
                                        dismiss()
                                    } label: {
                                        Text("加入包裹列表")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Palette.accent(store.settings.accentName))
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("查单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private func search() async {
        loading = true
        error = nil
        track = nil
        defer { loading = false }
        do {
            guard KdniaoService.shared.isLoggedIn else {
                throw KdniaoService.Failure.message("还没有填快递鸟 AppKey，去「设置 → 平台授权 → 快递鸟」")
            }
            track = try await KdniaoService.shared.query(mailNo: mailNo.trimmingCharacters(in: .whitespaces),
                                                         shipperCode: nil,
                                                         phone: phone)
            Haptic.tap()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func addParcel(_ t: KdTrack) {
        var p = Parcel()
        p.accountId = AccountStore.shared.active(.kdniao)?.id
        p.accountLabel = AccountStore.shared.active(.kdniao)?.label
        p.mailNo = t.mailNo
        p.companyCode = Courier.code(fromName: t.company)
        p.title = t.company
        p.code = t.pickupCode ?? ""
        p.status = t.isDelivered ? .picked : (p.code.isEmpty ? .transit : .awaiting)
        p.source = Platform.kdniao.rawValue
        if !p.code.isEmpty { p.arrivedAt = Date() }
        if t.isDelivered { p.pickedAt = Date() }
        p.track = t.nodes.map { TrackNode(time: $0.time, text: $0.text) }
        store.add(p)
        store.toast = "已加入 \(t.mailNo)"
    }
}

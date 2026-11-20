import SwiftUI
import WebKit

// MARK: - 隐藏页面收割器（京东 / 拼多多的订单页都靠它）

@MainActor
final class HarvestRunner: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private var steps: [(delay: Double, js: String?)] = []
    private var result: String?
    private var completion: ((String?) -> Void)?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    init(userAgent: String) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 780), configuration: cfg)
        super.init()
        web.navigationDelegate = self
        web.customUserAgent = userAgent
    }

    func start(url: URL, steps: [(Double, String?)], cookies: [StoredCookie] = [],
               completion: @escaping (String?) -> Void) {
        self.steps = steps
        self.completion = completion
        Task { [weak self] in
            guard let self else { return }
            await self.inject(cookies)
            self.web.load(URLRequest(url: url))
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 75_000_000_000)
                guard let self, !self.finished else { return }
                self.finish(self.result)
            }
        }
    }

    /// 把钥匙串里的登录态写回 WebView，重装/清缓存后也能直接进订单页
    private func inject(_ list: [StoredCookie]) async {
        guard !list.isEmpty else { return }
        let store = web.configuration.websiteDataStore.httpCookieStore
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for c in list {
                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: c.name, .value: c.value, .domain: c.domain, .path: c.path,
                ]
                if let e = c.expires { props[.expires] = e }
                guard let cookie = HTTPCookie(properties: props) else { continue }
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
    }

    /// 页面已经加载好时再来一轮（用户刚登录完）
    func resume(steps: [(Double, String?)], completion: @escaping (String?) -> Void) {
        finished = false
        self.steps = steps
        self.completion = completion
        runNext()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        runNext()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(result)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(result)
    }

    private func runNext() {
        guard !finished else { return }
        guard !steps.isEmpty else { finish(result); return }
        let step = steps.removeFirst()
        Task { [weak self] in
            guard let self else { return }
            if step.delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
            }
            if let js = step.js {
                if let v = try? await self.web.evaluateJavaScript(js),
                   let s = v as? String, !s.isEmpty, s != "null" {
                    self.result = s
                }
            }
            self.runNext()
        }
    }

    private func finish(_ text: String?) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        completion?(text)
        completion = nil
    }
}

struct RunnerWebView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 京东

enum JDHarvester {
    static let startURL = "https://my.m.jd.com/index.html?sceneval=2"
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    static let clickAll = #"""
    (function(){
      var els=[].slice.call(document.querySelectorAll('a,div,span,button'));
      for (var i=0;i<els.length;i++){
        var s=(els[i].textContent||'').trim();
        if(s==='全部订单'||s==='查看全部订单'){ els[i].click(); return 'clicked'; }
      }
      var m=document.querySelector('.my_order_entrance');
      if(m){ m.click(); return 'entrance'; }
      return 'none';
    })()
    """#

    static let scroll = "window.scrollTo(0, document.body.scrollHeight); 'ok'"

    static let discover = #"""
    (function(){
      function txt(el){ return el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
      function cardOf(el){
        var n = el;
        while (n && n.parentElement) {
          n = n.parentElement;
          if (n.querySelector && n.querySelector('[class*="order_item"]')) return n;
        }
        return null;
      }
      var out = [], seen = {};
      [].slice.call(document.querySelectorAll('[class*="order_state"]')).forEach(function(st){
        var card = cardOf(st) || st.parentElement;
        if (!card) return;
        var ep = card.querySelector('[data-eparam]');
        var json = {};
        if (ep) {
          var raw = ep.getAttribute('data-eparam') || '';
          try { json = JSON.parse(raw) } catch (e) { try { json = JSON.parse(raw.replace(/&quot;/g, '"')) } catch (e2) {} }
        }
        var id = String(json.orderid || '');
        if (!/^\d{8,}$/.test(id) || seen[id]) return;
        seen[id] = 1;
        var cardTxt = txt(card);
        var tm = cardTxt.match(/20\d{2}[-\/]\d{1,2}[-\/]\d{1,2}(?:\s+\d{1,2}:\d{1,2}(?::\d{1,2})?)?/);
        out.push({
          orderId: id,
          statusHint: txt(st),
          shopName: txt(card.querySelector('[class*="shop_title"]')),
          itemTitle: txt(card.querySelector('[class*="desc"]')),
          delivery: txt(card.querySelector('[class*="order_wuliubar"]')),
          timeText: tm ? tm[0] : ''
        });
      });
      return JSON.stringify({ items: out, url: location.href, title: document.title, body: (document.body.innerText||'').slice(0,1500) });
    })()
    """#

    struct Item: Decodable {
        var orderId: String
        var statusHint: String
        var shopName: String
        var itemTitle: String
        var delivery: String
        var timeText: String
    }

    struct Envelope: Decodable {
        var items: [Item]
        var url: String
        var title: String
        var body: String
    }

    static func parse(_ raw: String) -> (items: [Parcel], note: String) {
        guard let data = raw.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return ([], "京东页面没解析到订单，可能未登录或被风控")
        }
        var out: [Parcel] = []
        for it in env.items {
            var p = Parcel()
            p.orderId = it.orderId
            p.title = it.itemTitle.isEmpty ? (it.shopName.isEmpty ? "京东订单" : it.shopName) : it.itemTitle
            p.source = Platform.jd.rawValue
            let text = "\(it.itemTitle) \(it.delivery) \(it.statusHint)"
            let parsed = DeliveryParser.parse("\(it.delivery)\n\(it.itemTitle)")
            p.code = parsed.code ?? ""
            p.mailNo = parsed.mailNo
            p.companyCode = Courier.code(fromName: parsed.company ?? it.delivery)
            p.station = parsed.station ?? ""
            p.status = status(text, hasCode: !p.code.isEmpty)
            if p.status == .awaiting { p.arrivedAt = Date() }
            if p.status == .picked { p.pickedAt = parseTime(it.timeText) ?? Date() }
            if !it.delivery.isEmpty {
                p.track = [TrackNode(time: Fmt.mmddhm(), text: it.delivery)]
            }
            p.createdAt = parseTime(it.timeText) ?? Date()
            out.append(p)
        }
        let note = env.items.isEmpty
            ? (env.title.contains("登录") ? "京东未登录" : "京东没有待收货订单（\(env.title)）")
            : "京东解析到 \(env.items.count) 条订单"
        return (out, note)
    }

    static func status(_ text: String, hasCode: Bool) -> ParcelStatus {
        func hit(_ pattern: String) -> Bool {
            text.range(of: pattern, options: .regularExpression) != nil
        }
        if hit("已完成|已签收|交易完成|已收货") { return .picked }
        if hit("待发货|未发货|待出库|备货|已下单") { return .transit }
        if hasCode { return .awaiting }
        if hit("待收货|运输|派送|揽收|已发货|配送|待取件") { return .transit }
        return .transit
    }

    static func parseTime(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - 拼多多

enum PDDHarvester {
    static let startURL = "https://mobile.yangkeduo.com/orders.html"
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    static let scroll = "window.scrollTo(0, document.body.scrollHeight); 'ok'"

    static let discover = #"""
    (function(){
      var out=[], seen={};
      var as=[].slice.call(document.querySelectorAll('a[href*="order_sn"],a[href*="order_detail"]'));
      as.forEach(function(a){
        var m=(a.getAttribute('href')||'').match(/order_sn=([0-9]{6,}-?[0-9]{6,})/);
        if(!m) return;
        var id=m[1];
        if(seen[id]) return;
        seen[id]=1;
        var card=a;
        for(var i=0;i<6 && card.parentElement;i++){
          card=card.parentElement;
          if((card.innerText||'').length>60) break;
        }
        out.push({orderSn:id,text:(card.innerText||'').replace(/\s+/g,' ').slice(0,400)});
      });
      if(out.length===0){
        var body=(document.body.innerText||'');
        var re=/order_sn=([0-9]{6,}-?[0-9]{6,})/g, mm, html=document.documentElement.innerHTML;
        while((mm=re.exec(html))){ if(!seen[mm[1]]){ seen[mm[1]]=1; out.push({orderSn:mm[1],text:body.slice(0,200)}); } }
      }
      return JSON.stringify({url:location.href,title:document.title,items:out,body:(document.body.innerText||'').slice(0,2000)});
    })()
    """#

    struct Item: Decodable {
        var orderSn: String
        var text: String
    }

    struct Envelope: Decodable {
        var url: String
        var title: String
        var items: [Item]
        var body: String
    }

    static func parse(_ raw: String) -> (items: [Parcel], note: String) {
        guard let data = raw.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return ([], "拼多多页面没解析到订单")
        }
        var out: [Parcel] = []
        for it in env.items {
            var p = Parcel()
            p.orderId = it.orderSn
            p.source = Platform.pdd.rawValue
            let parsed = DeliveryParser.parse(it.text)
            p.code = parsed.code ?? ""
            p.mailNo = parsed.mailNo
            p.companyCode = Courier.code(fromName: parsed.company ?? it.text)
            p.station = parsed.station ?? ""
            p.title = titleFrom(it.text)
            p.status = JDHarvester.status(it.text, hasCode: !p.code.isEmpty)
            if p.status == .awaiting { p.arrivedAt = Date() }
            if p.status == .picked { p.pickedAt = Date() }
            p.track = [TrackNode(time: Fmt.mmddhm(), text: it.text)]
            out.append(p)
        }
        let note = env.items.isEmpty
            ? (env.title.contains("登录") ? "拼多多未登录" : "拼多多没解析到订单（\(env.title)）")
            : "拼多多解析到 \(env.items.count) 条订单"
        return (out, note)
    }

    static func titleFrom(_ text: String) -> String {
        // 卡片文案形如「商品名 已发货 …」，取前 24 个字符当标题
        let cut = text.split(separator: " ").prefix(6).joined(separator: " ")
        return String(cut.prefix(30))
    }
}

// MARK: - 同步页

struct HarvestSheet: View {
    let platform: Platform
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    @State private var runner: HarvestRunner? = nil
    @State private var note = "正在打开订单页…"
    @State private var finished = false
    @State private var working = true

    private var accent: Color { Palette.accent(store.settings.accentName) }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                if let runner {
                    RunnerWebView(web: runner.web)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Palette.bg.ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    if working {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "info.circle.fill").foregroundStyle(Palette.secondary)
                    }
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial)
            }
            .navigationTitle("同步\(platform.title)订单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        rerun()
                    } label: {
                        Text("重新解析").bold()
                    }
                    .tint(accent)
                    .disabled(working)
                }
            }
        }
        .task { start() }
    }

    private var steps: [(Double, String?)] {
        if platform == .jd {
            return [
                (2.0, JDHarvester.clickAll),
                (3.5, JDHarvester.scroll),
                (1.0, JDHarvester.scroll),
                (1.0, JDHarvester.discover),
            ]
        }
        return [
            (3.5, PDDHarvester.scroll),
            (1.2, PDDHarvester.scroll),
            (1.0, PDDHarvester.discover),
        ]
    }

    private func start() {
        guard runner == nil else { return }
        let r = HarvestRunner(userAgent: platform == .jd ? JDHarvester.ua : PDDHarvester.ua)
        runner = r
        let url = URL(string: platform == .jd ? JDHarvester.startURL : PDDHarvester.startURL)!
        working = true
        r.start(url: url, steps: steps,
                cookies: PlatformSession.shared.cookies(for: platform)) { raw in complete(raw) }
    }

    private func rerun() {
        guard let runner else { start(); return }
        working = true
        note = "正在解析当前页面…"
        runner.resume(steps: steps) { raw in complete(raw) }
    }

    private func complete(_ raw: String?) {
        guard let raw else {
            note = "页面还没加载完，登录后点「重新解析」"
            working = false
            finished = true
            return
        }
        let result = platform == .jd ? JDHarvester.parse(raw) : PDDHarvester.parse(raw)
        var added = 0
        let acc = AccountStore.shared.active(platform)
        for var p in result.items {
            p.accountId = acc?.id
            p.accountLabel = acc?.label
            if let existing = store.parcels.firstIndex(where: { $0.orderId != nil && $0.orderId == p.orderId }) {
                store.parcels[existing].status = p.status
                store.parcels[existing].code = p.code.isEmpty ? store.parcels[existing].code : p.code
                if let m = p.mailNo { store.parcels[existing].mailNo = m }
                continue
            }
            store.parcels.insert(p, at: 0)
            added += 1
        }
        store.lastSync = Date()
        store.save()
        working = false
        finished = true
        note = added == 0 ? result.note : "\(result.note)，新增 \(added) 件"
        store.toast = note
        if added > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        }
    }
}

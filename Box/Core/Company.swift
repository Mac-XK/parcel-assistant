import SwiftUI

// MARK: - 快递公司

enum Courier {
    struct Info {
        let name: String
        let asset: String?
        /// 透明底品牌图铺的底色
        let tile: String
    }

    /// 编号与 Scripting 版 theme.companyName 完全一致
    static func name(_ code: Int) -> String {
        switch code {
        case 1: return "中通快递"
        case 2: return "顺丰速运"
        case 3: return "圆通速递"
        case 4: return "韵达快递"
        case 5: return "申通快递"
        case 6: return "极兔速递"
        case 7: return "中国邮政"
        case 8: return "京东物流"
        case 9: return "德邦快递"
        case 10: return "丰巢"
        case 11: return "菜鸟驿站"
        case 12: return "百世快递"
        case 13: return "天天快递"
        case 14: return "宅急送"
        case 15: return "苏宁物流"
        case 16: return "DHL"
        case 17: return "联邦快递"
        case 18: return "UPS"
        case 19: return "达达快送"
        case 20: return "闪送"
        case 21: return "顺丰同城"
        default: return "其他快递"
        }
    }

    static func asset(_ code: Int) -> String? {
        switch code {
        case 1: return "zto"
        case 2, 21: return "sf_white"
        case 3: return "yto"
        case 4: return "yunda"
        case 5: return "sto"
        case 6: return "jtexpress"
        case 7: return "china_post"
        case 8: return "jd"
        case 9: return "debang"
        case 10: return "hive"
        case 11: return "cainiao"
        case 12: return "best"
        case 16: return "dhl"
        case 17: return "fedex"
        case 18: return "ups"
        case 19: return "dada"
        case 20: return "shansong"
        default: return nil
        }
    }

    static func tile(_ code: Int) -> Color {
        switch code {
        case 2: return Color(hex: "#111111")
        case 5: return Color(hex: "#FF5D00")
        case 10: return Color(hex: "#F5C400")
        case 16: return Color(hex: "#FFCC00")
        case 18: return Color(hex: "#2E130B")
        case 20: return Color(hex: "#2F7BF6")
        default: return Color(light: "#F1F1F4", dark: "#2A2A2C")
        }
    }

    /// 文案里的公司名 → 编号（识别与导入兜底）
    static func code(fromName hint: String) -> Int {
        let t = hint.isEmpty ? "" : hint
        if t.contains("菜鸟") || t.contains("驿站") { return 11 }
        if t.contains("丰巢") || t.contains("快递柜") { return 10 }
        if t.contains("京东") { return 8 }
        if t.contains("顺丰") { return 2 }
        if t.contains("中通") { return 1 }
        if t.contains("圆通") { return 3 }
        if t.contains("韵达") { return 4 }
        if t.contains("申通") { return 5 }
        if t.contains("极兔") || t.uppercased().contains("J&T") { return 6 }
        if t.contains("德邦") { return 9 }
        if t.contains("百世") || t.contains("汇通") { return 12 }
        if t.contains("邮政") || t.contains("EMS") { return 7 }
        if t.contains("天天") { return 13 }
        if t.contains("宅急送") { return 14 }
        if t.contains("苏宁") { return 15 }
        if t.uppercased().contains("DHL") { return 16 }
        if t.uppercased().contains("FEDEX") || t.contains("联邦") { return 17 }
        if t.uppercased().contains("UPS") { return 18 }
        if t.contains("达达") { return 19 }
        if t.contains("闪送") { return 20 }
        return 0
    }
}

// MARK: - 平台

enum Platform: String, CaseIterable, Identifiable, Codable {
    case taobao, cainiao, jd, pdd, fengchao, mi, kdniao

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taobao: return "淘宝"
        case .cainiao: return "菜鸟"
        case .jd: return "京东"
        case .pdd: return "拼多多"
        case .fengchao: return "丰巢"
        case .mi: return "小米快递"
        case .kdniao: return "快递鸟"
        }
    }

    var asset: String {
        switch self {
        case .taobao: return "taobao"
        case .cainiao: return "cainiao"
        case .jd: return "jd"
        case .pdd: return "pdd"
        case .fengchao: return "hive"
        case .mi: return "mi"
        case .kdniao: return "kdniao"
        }
    }

    var loginURL: URL? {
        switch self {
        case .taobao: return URL(string: "https://login.taobao.com/member/login.jhtml")
        case .cainiao: return URL(string: "https://login.taobao.com/member/login.jhtml")
        case .jd: return URL(string: "https://plogin.m.jd.com/login/login?appid=0&returnurl=https%3A%2F%2Fhome.m.jd.com%2FmyJd%2Fnewhome.action")
        case .pdd: return URL(string: "https://mobile.yangkeduo.com/login.html")
        case .fengchao: return URL(string: "https://consumer.fcbox.com")
        case .mi: return URL(string: "https://account.xiaomi.com/pass/serviceLogin?sid=assistant&_locale=zh_CN&_uRegion=CN")
        case .kdniao: return URL(string: "https://biz.kdniao.com/login")
        }
    }

    /// 登录页 cookie 域名过滤
    var cookieDomains: [String] {
        switch self {
        case .taobao, .cainiao: return ["taobao.com", "tmall.com", "alibaba.com"]
        case .jd: return ["jd.com", "360buy.com"]
        case .pdd: return ["yangkeduo.com", "pinduoduo.com"]
        case .fengchao: return ["fcbox.com"]
        case .mi: return ["xiaomi.com", "mi.com"]
        case .kdniao: return ["kdniao.com"]
        }
    }

    /// 判定「真的登录了」的 cookie，而不是登录页下发的匿名 cookie
    var sessionCookies: [String] {
        switch self {
        case .taobao, .cainiao: return ["unb", "tracknick"]
        case .jd: return ["pt_key", "pt_pin"]
        case .pdd: return ["pdd_user_id", "PDDAccessToken", "api_uid"]
        case .fengchao: return ["token", "Authorization"]
        case .mi: return ["passToken", "serviceToken"]
        case .kdniao: return ["kdniao_token", "token"]
        }
    }

    var note: String {
        switch self {
        case .taobao: return "官方登录页授权，存 Cookie"
        case .cainiao: return "没有独立账号，登录淘宝即生效"
        case .jd: return "plogin 登录，取 pt_key"
        case .pdd: return "手机号登录页授权"
        case .fengchao: return "手机号 + 短信验证码"
        case .mi: return "小米账号密码 / 短信登录"
        case .kdniao: return "使用自己的快递鸟账号"
        }
    }
}

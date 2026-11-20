import Foundation
import CommonCrypto
import Security

// MARK: - 散列 / 对称加密

enum Crypto {
    static func md5Hex(_ s: String) -> String {
        let data = Data(s.utf8)
        var d = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &d) }
        return d.map { String(format: "%02x", $0) }.joined()
    }

    static func sha1(_ data: Data) -> Data {
        var d = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &d) }
        return Data(d)
    }

    static func sha1Hex(_ s: String) -> String {
        sha1(Data(s.utf8)).map { String(format: "%02X", $0) }.joined()
    }

    static func sha1Base64(_ s: String) -> String {
        sha1(Data(s.utf8)).base64EncodedString()
    }

    /// AES-128-ECB/PKCS7（小米快递用）
    static func aesECB(_ data: Data, key: String, decrypt: Bool) -> Data? {
        let keyData = Data(key.utf8)
        let outLen = data.count + kCCBlockSizeAES128
        var out = [UInt8](repeating: 0, count: outLen)
        var moved = 0
        let status = data.withUnsafeBytes { inBuf in
            keyData.withUnsafeBytes { kBuf in
                CCCrypt(decrypt ? CCOperation(kCCDecrypt) : CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        kBuf.baseAddress, keyData.count,
                        nil,
                        inBuf.baseAddress, data.count,
                        &out, outLen, &moved)
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(out.prefix(moved))
    }
}

// MARK: - RSA（丰巢签名用 PKCS#1 v1.5）

enum RSA {
    /// 读一个 DER TLV：返回 (tag, 内容起点, 长度, 下一个 TLV 起点)
    private static func tlv(_ bytes: [UInt8], _ pos: Int) -> (tag: UInt8, start: Int, len: Int, next: Int)? {
        guard pos + 1 < bytes.count else { return nil }
        let tag = bytes[pos]
        var p = pos + 1
        var len = Int(bytes[p]); p += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            len = 0
            for _ in 0..<n {
                guard p < bytes.count else { return nil }
                len = len * 256 + Int(bytes[p]); p += 1
            }
        }
        guard p + len <= bytes.count else { return nil }
        return (tag, p, len, p + len)
    }

    /// SPKI(base64) → RSA 公钥的 PKCS#1 DER
    static func pkcs1(fromSPKI der: [UInt8]) -> Data? {
        guard let top = tlv(der, 0), top.tag == 0x30,
              let alg = tlv(der, top.start), alg.tag == 0x30 else { return nil }
        guard let bit = tlv(der, alg.next), bit.tag == 0x03 else { return nil }
        // BIT STRING 内容首字节是 unused bits
        let innerStart = bit.start + 1
        guard let seq = tlv(der, innerStart), seq.tag == 0x30 else { return nil }
        return Data(der[innerStart..<seq.next])
    }

    static func publicKey(spkiBase64: String) -> SecKey? {
        let clean = spkiBase64.replacingOccurrences(of: "[^A-Za-z0-9+/=]", with: "", options: .regularExpression)
        guard let data = Data(base64Encoded: clean),
              let pkcs1 = pkcs1(fromSPKI: [UInt8](data)) else { return nil }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: pkcs1.count * 8,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error)
    }

    /// 用丰巢下发的公钥做 PKCS1v15 加密，返回 base64
    static func encryptPKCS1(_ text: String, spkiBase64: String) -> String? {
        guard let key = publicKey(spkiBase64: spkiBase64) else { return nil }
        var error: Unmanaged<CFError>?
        guard let out = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, Data(text.utf8) as CFData, &error) else {
            return nil
        }
        return (out as Data).base64EncodedString()
    }
}

// MARK: - 简易表单编码

enum Form {
    static func encode(_ pairs: [(String, String)]) -> Data {
        pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

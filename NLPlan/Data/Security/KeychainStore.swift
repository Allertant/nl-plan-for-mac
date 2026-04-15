import Foundation

/// API Key 安全存储
///
/// 使用 UserDefaults + Base64 编码存储，避免 macOS Keychain 对未签名应用反复弹窗要求输入密码。
/// 正式签名分发后可按需迁移回 Keychain Services。
final class KeychainStore {

    static let shared = KeychainStore()

    /// 存储前缀，避免与其它 UserDefaults key 冲突
    private let prefix = "com.nlplan.mac.secure."

    private let defaults = UserDefaults.standard

    private init() {}

    func save(key: String, value: String) throws {
        let encoded = Data(value.utf8).base64EncodedString()
        defaults.set(encoded, forKey: prefixed(key))
    }

    func load(key: String) -> String? {
        guard let encoded = defaults.string(forKey: prefixed(key)) else {
            return nil
        }
        guard let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) throws {
        defaults.removeObject(forKey: prefixed(key))
    }

    // MARK: - Private

    private func prefixed(_ key: String) -> String {
        return prefix + key
    }
}


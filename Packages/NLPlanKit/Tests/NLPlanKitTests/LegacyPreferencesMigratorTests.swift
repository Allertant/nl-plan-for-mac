import Testing
import Foundation
@testable import NLPlanKit

@Suite("LegacyPreferencesMigrator Tests")
struct LegacyPreferencesMigratorTests {

    @Test("从旧偏好域回填缺失配置")
    func migrateMissingValuesFromLegacyDomain() {
        let suiteName = "legacy-migration-\(UUID().uuidString)"
        let legacyDomainName = "legacy-domain-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)

        let legacyValues: [String: Any] = [
            AppConstants.secureStoragePrefix + AppConstants.apiKeyKeychainKey: Data("secret-key".utf8).base64EncodedString(),
            AppConstants.selectedModelKey: "deepseek-reasoner",
            AppConstants.appearanceModeKey: "dark",
            AppConstants.workEndTimeKey: 22.5,
            AppConstants.tagsKey: ["工作", "学习"]
        ]

        defaults.setPersistentDomain(legacyValues, forName: legacyDomainName)

        LegacyPreferencesMigrator.migrateIfNeeded(
            currentDefaults: defaults,
            legacyDomainName: legacyDomainName
        )

        #expect(defaults.string(forKey: AppConstants.secureStoragePrefix + AppConstants.apiKeyKeychainKey) == legacyValues[AppConstants.secureStoragePrefix + AppConstants.apiKeyKeychainKey] as? String)
        #expect(defaults.string(forKey: AppConstants.selectedModelKey) == "deepseek-reasoner")
        #expect(defaults.string(forKey: AppConstants.appearanceModeKey) == "dark")
        #expect(defaults.double(forKey: AppConstants.workEndTimeKey) == 22.5)
        #expect(defaults.stringArray(forKey: AppConstants.tagsKey) == ["工作", "学习"])

        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)
    }

    @Test("不覆盖新偏好域中已有的值")
    func doesNotOverrideExistingValues() {
        let suiteName = "legacy-migration-\(UUID().uuidString)"
        let legacyDomainName = "legacy-domain-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)

        defaults.set("deepseek-chat", forKey: AppConstants.selectedModelKey)
        defaults.setPersistentDomain([
            AppConstants.selectedModelKey: "deepseek-reasoner"
        ], forName: legacyDomainName)

        LegacyPreferencesMigrator.migrateIfNeeded(
            currentDefaults: defaults,
            legacyDomainName: legacyDomainName
        )

        #expect(defaults.string(forKey: AppConstants.selectedModelKey) == "deepseek-chat")

        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)
    }
}

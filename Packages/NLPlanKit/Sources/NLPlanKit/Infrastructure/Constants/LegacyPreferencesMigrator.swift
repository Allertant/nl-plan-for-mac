import Foundation

enum LegacyPreferencesMigrator {

    static func migrateIfNeeded(
        currentDefaults: UserDefaults = .standard,
        legacyDomainName: String = AppConstants.legacyPreferencesDomain
    ) {
        guard let legacyDomain = currentDefaults.persistentDomain(forName: legacyDomainName) else {
            return
        }

        let directKeysToMigrate: Set<String> = [
            AppConstants.selectedModelKey,
            AppConstants.selectedReasoningEffortKey,
            AppConstants.appearanceModeKey,
            AppConstants.workEndTimeKey,
            AppConstants.tagsKey
        ]

        var migratedAnyValue = false

        for (key, value) in legacyDomain {
            guard shouldMigrate(key: key, directKeysToMigrate: directKeysToMigrate) else {
                continue
            }

            guard currentDefaults.object(forKey: key) == nil else {
                continue
            }

            currentDefaults.set(value, forKey: key)
            migratedAnyValue = true
        }

        if migratedAnyValue {
            currentDefaults.synchronize()
        }
    }

    private static func shouldMigrate(key: String, directKeysToMigrate: Set<String>) -> Bool {
        if directKeysToMigrate.contains(key) {
            return true
        }

        return key.hasPrefix(AppConstants.secureStoragePrefix)
    }
}

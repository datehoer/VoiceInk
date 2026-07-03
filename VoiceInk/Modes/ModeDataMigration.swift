import Foundation

extension ModeManager {
    func migratedModeConfigurationData(for configKey: String) -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: configKey) {
            return data
        }

        guard let legacyData = defaults.data(forKey: LegacyModeDataKey.configurations) else {
            return nil
        }

        defaults.set(legacyData, forKey: configKey)
        return legacyData
    }

    func migrateLoadedModeConfigurationsIfNeeded() {
        var didChange = false

        for index in configurations.indices {
            var config = configurations[index]
            var changedConfig = false

            if config.selectedTranscriptionModelName == nil {
                config.selectedTranscriptionModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
                changedConfig = true
            }

            if config.selectedLanguage == nil {
                config.selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
                changedConfig = true
            }

            if config.selectedAIProvider == nil {
                config.selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
                changedConfig = true
            }

            if config.selectedAIModel == nil,
               let provider = config.selectedAIProvider {
                config.selectedAIModel = UserDefaults.standard.string(forKey: "\(provider)SelectedModel")
                changedConfig = true
            }

            if config.isAIEnhancementEnabled && config.selectedPrompt == nil {
                config.selectedPrompt = UserDefaults.standard.string(forKey: "selectedPromptId")
                changedConfig = true
            }

            if changedConfig {
                configurations[index] = config
                didChange = true
            }
        }

        if migrateStarterEnhancementDefaultIfNeeded() {
            didChange = true
        }

        if didChange {
            saveConfigurations()
        }

        migrateLegacyShortcutStorageIfNeeded()
    }

    private func migrateStarterEnhancementDefaultIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: StarterModeEnhancementDefaultMigration.userDefaultsKey) else {
            return false
        }

        let activeConfigurationID = defaults.string(forKey: ModeConfigurationStorageKey.activeConfigurationId)
            .flatMap(UUID.init(uuidString:))
        let result = StarterModeEnhancementDefaultMigration.upgraded(
            configurations: configurations,
            activeConfigurationID: activeConfigurationID
        )

        defaults.set(true, forKey: StarterModeEnhancementDefaultMigration.userDefaultsKey)

        guard result.didChange else {
            return false
        }

        configurations = result.configurations

        if result.activeConfigurationID != activeConfigurationID {
            defaults.set(result.activeConfigurationID?.uuidString, forKey: ModeConfigurationStorageKey.activeConfigurationId)
        }

        return true
    }

    private func migrateLegacyShortcutStorageIfNeeded() {
        let defaults = UserDefaults.standard

        for config in configurations {
            let oldShortcutKey = "\(LegacyModeDataKey.shortcutPrefix)\(config.id.uuidString)"
            let newShortcutKey = ShortcutAction.mode(config.id).userDefaultsKey

            if defaults.object(forKey: newShortcutKey) == nil,
               let oldShortcutData = defaults.data(forKey: oldShortcutKey) {
                defaults.set(oldShortcutData, forKey: newShortcutKey)
            }

            let oldClearedKey = "\(oldShortcutKey)_cleared"
            let newClearedKey = "\(newShortcutKey)_cleared"
            if defaults.object(forKey: newClearedKey) == nil,
               defaults.object(forKey: oldClearedKey) != nil {
                defaults.set(defaults.bool(forKey: oldClearedKey), forKey: newClearedKey)
            }
        }
    }
}

private enum LegacyModeDataKey {
    static let configurations = "powerModeConfigurationsV2"
    static let shortcutPrefix = "Shortcut_powerMode_"
}

private enum ModeConfigurationStorageKey {
    static let activeConfigurationId = "activeConfigurationId"
}

struct StarterModeEnhancementDefaultMigrationResult {
    var configurations: [ModeConfig]
    var activeConfigurationID: UUID?
    var didChange: Bool
}

enum StarterModeEnhancementDefaultMigration {
    static let userDefaultsKey = "StarterModeEnhancementDefaultMigrationCompleted"

    static func upgraded(
        configurations: [ModeConfig],
        activeConfigurationID: UUID?
    ) -> StarterModeEnhancementDefaultMigrationResult {
        let cleanID = StarterModeCatalog.cleanModeID
        let enhancementID = StarterModeCatalog.enhancementModeID

        guard configurations.contains(where: { $0.id == cleanID }),
              configurations.contains(where: { $0.id == enhancementID }) else {
            return StarterModeEnhancementDefaultMigrationResult(
                configurations: configurations,
                activeConfigurationID: activeConfigurationID,
                didChange: false
            )
        }

        let currentDefault = configurations.first { $0.isDefault }
        if let currentDefault,
           currentDefault.id != cleanID {
            return StarterModeEnhancementDefaultMigrationResult(
                configurations: configurations,
                activeConfigurationID: activeConfigurationID,
                didChange: false
            )
        }

        var updatedConfigurations = configurations
        var didChange = false

        for index in updatedConfigurations.indices {
            if updatedConfigurations[index].id == cleanID,
               updatedConfigurations[index].isDefault {
                updatedConfigurations[index].isDefault = false
                didChange = true
            }

            if updatedConfigurations[index].id == enhancementID,
               !updatedConfigurations[index].isDefault {
                updatedConfigurations[index].isDefault = true
                didChange = true
            }
        }

        var updatedActiveID = activeConfigurationID
        if activeConfigurationID == cleanID {
            updatedActiveID = enhancementID
            didChange = true
        }

        return StarterModeEnhancementDefaultMigrationResult(
            configurations: updatedConfigurations,
            activeConfigurationID: updatedActiveID,
            didChange: didChange
        )
    }
}

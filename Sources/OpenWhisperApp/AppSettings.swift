import Foundation

struct AppSettings: Codable {
    var asrProvider: String?
    var whisperkitModel: String?
    var whisperkitLanguage: String?
    var cleanupEnabled: Bool?
    var cleanupUserDictionary: String?
}

enum AppSettingsPaths {
    static func defaultSettingsURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("OpenWhisper", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }
}

final class AppSettingsStore {
    private let settingsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(settingsURL: URL? = nil) {
        if let settingsURL {
            self.settingsURL = settingsURL
        } else {
            self.settingsURL = (try? AppSettingsPaths.defaultSettingsURL())
                ?? URL(fileURLWithPath: NSString(string: "~/.dictation/settings.json").expandingTildeInPath)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return AppSettings()
        }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(_ settings: AppSettings) throws {
        let directory = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    func pathDescription() -> String {
        settingsURL.path
    }
}

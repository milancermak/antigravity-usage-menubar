import Foundation

public struct UsageSettings: Codable, Equatable, Sendable {
    public var iconMode: MenuBarIconMode
    public var singleIconWindow: QuotaWindowKind
    public var showPercentageLabel: Bool
    public var pollIntervalSeconds: Int
    public var paceMethod: PaceMethod
    public var greenHeadroomPercent: Double
    public var redRemainingPercent: Double
    public var agyPathOverride: String

    public init(
        iconMode: MenuBarIconMode = .both,
        singleIconWindow: QuotaWindowKind = .weekly,
        showPercentageLabel: Bool = true,
        pollIntervalSeconds: Int = 60,
        paceMethod: PaceMethod = .cycleAverage,
        greenHeadroomPercent: Double = 15.0,
        redRemainingPercent: Double = 10.0,
        agyPathOverride: String = ""
    ) {
        self.iconMode = iconMode
        self.singleIconWindow = singleIconWindow
        self.showPercentageLabel = showPercentageLabel
        self.pollIntervalSeconds = pollIntervalSeconds
        self.paceMethod = paceMethod
        self.greenHeadroomPercent = greenHeadroomPercent
        self.redRemainingPercent = redRemainingPercent
        self.agyPathOverride = agyPathOverride
    }

    public static let pollIntervalChoices: [Int] = [30, 60, 120, 300, 600]
}

public enum UsageSettingsStore {
    private static let key = "com.agyusagemenubar.settings.v1"

    public static func load(from defaults: UserDefaults = .standard) -> UsageSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(UsageSettings.self, from: data) else {
            return UsageSettings()
        }
        return decoded
    }

    public static func save(_ settings: UsageSettings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}

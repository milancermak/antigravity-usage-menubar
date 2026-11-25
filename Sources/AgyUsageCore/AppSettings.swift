import Foundation

public struct UsageSettings: Codable, Equatable, Sendable {
    public var menuBarDisplay: MenuBarDisplay
    public var showPercentageLabel: Bool
    public var pollIntervalSeconds: Int
    public var paceMethod: PaceMethod
    public var safetyMarginPercent: Double
    public var agyPathOverride: String

    public init(
        menuBarDisplay: MenuBarDisplay = .both,
        showPercentageLabel: Bool = true,
        pollIntervalSeconds: Int = 60,
        paceMethod: PaceMethod = .cycleAverage,
        safetyMarginPercent: Double = 15.0,
        agyPathOverride: String = ""
    ) {
        self.menuBarDisplay = menuBarDisplay
        self.showPercentageLabel = showPercentageLabel
        self.pollIntervalSeconds = pollIntervalSeconds
        self.paceMethod = paceMethod
        self.safetyMarginPercent = safetyMarginPercent
        self.agyPathOverride = agyPathOverride
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarDisplay
        case showPercentageLabel
        case pollIntervalSeconds
        case paceMethod
        case safetyMarginPercent
        case greenHeadroomPercent
        case agyPathOverride
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarDisplay = try c.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay) ?? .both
        showPercentageLabel = try c.decodeIfPresent(Bool.self, forKey: .showPercentageLabel) ?? true
        pollIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 60
        paceMethod = try c.decodeIfPresent(PaceMethod.self, forKey: .paceMethod) ?? .cycleAverage
        safetyMarginPercent = try c.decodeIfPresent(Double.self, forKey: .safetyMarginPercent)
            ?? c.decodeIfPresent(Double.self, forKey: .greenHeadroomPercent)
            ?? 15.0
        agyPathOverride = try c.decodeIfPresent(String.self, forKey: .agyPathOverride) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(menuBarDisplay, forKey: .menuBarDisplay)
        try c.encode(showPercentageLabel, forKey: .showPercentageLabel)
        try c.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
        try c.encode(paceMethod, forKey: .paceMethod)
        try c.encode(safetyMarginPercent, forKey: .safetyMarginPercent)
        try c.encode(agyPathOverride, forKey: .agyPathOverride)
    }

    public static let pollIntervalChoices: [Int] = [30, 60, 120, 300, 600]
}

public enum UsageSettingsStore {
    private static let key = "com.agyusagemenubar.settings.v2"

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

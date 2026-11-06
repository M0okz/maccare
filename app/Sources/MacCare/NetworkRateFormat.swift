import Foundation

enum NetworkRateFormat {
    /// Les compteurs sont en octets/s ; un mégabit vaut 1 000 000 bits.
    static func megabits(_ bytesPerSecond: Double?) -> String { value(bytesPerSecond) + " Mb/s" }

    static func value(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        let rate = bytesPerSecond * 8 / 1_000_000
        guard rate.isFinite else { return "—" }
        return rate.formatted(.number.locale(Locale(identifier: "fr_FR")).grouping(.never).precision(.fractionLength(2)))
    }
}

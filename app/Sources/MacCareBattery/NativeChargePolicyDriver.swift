import Foundation
import CoreFoundation
import Darwin
import CMacCarePowerUI

// Preference contract reference (independent implementation):
// https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/Sources/Shared/NativeChargeLimit.swift

/// A preference value whose absence and Boolean type survive recovery.
public enum NativeChargePolicyPreferenceValue: Codable, Equatable, Sendable {
    case absent
    case integer(Int)
    case boolean(Bool)
}

/// The two owned preferences in root's manual charge-limit domain.
public struct NativeChargePolicyPreferences: Codable, Equatable, Sendable {
    public let featureState: NativeChargePolicyPreferenceValue
    public let limit: NativeChargePolicyPreferenceValue

    /// Captures values without normalizing absent keys or Boolean feature states.
    public init(featureState: NativeChargePolicyPreferenceValue, limit: NativeChargePolicyPreferenceValue) {
        self.featureState = featureState; self.limit = limit
    }

    /// Whether the feature is explicitly enabled; nil means its key is absent or invalid.
    public var featureEnabled: Bool? {
        switch featureState {
        case .boolean(let value): return value
        case .integer(0): return false
        case .integer(1): return true
        default: return nil
        }
    }

    /// Whether both keys can be restored without inventing a target.
    public var isValid: Bool {
        switch featureState {
        case .absent, .boolean, .integer(0), .integer(1): break
        default: return false
        }
        switch limit {
        case .absent: return featureEnabled != true
        case .integer(let value): return (1...100).contains(value)
        case .boolean: return false
        }
    }
}

/// A closed preference policy, separate from the slider-limited PowerUI driver.
/// Calls belong to the helper's serial battery queue. A successful preference
/// write does not claim that powerd or the firmware has applied the target yet.
public protocol NativeChargePolicyDriver {
    /// Whether the complete read/release interface is present; discovery writes nothing.
    var isAvailable: Bool { get }
    /// Captures two consistent reads, preserving missing keys and Boolean values.
    func readPreferences() throws -> NativeChargePolicyPreferences
    /// Writes and confirms a target from 1 through 100 in preferences, not in firmware.
    func apply(limit: Int) throws
    /// Releases the agent's manual limit without replacing the saved preferences.
    func clearRegisteredLimit() throws
    /// Restores the exact saved keys, including deletion of keys initially absent.
    func restorePreferences(_ snapshot: NativeChargePolicyPreferences) throws
    /// Returns the unique registered target, nil for an explicit empty result, or throws.
    func registeredLimit() throws -> Int?
    /// Returns nil when the Apple calibration override cannot be determined.
    func calibrationOverride() -> Bool?
}

/// Fixed keys accepted by the root-only preference store; callers supply no domain or path.
enum NativeChargePolicyPreferenceKey: String {
    case featureState = "MCLFeatureState"
    case limit = "mclLimitValue"
}

/// Injectable access to only the two manual charge-limit preferences.
protocol NativeChargePolicyPreferenceStore {
    func value(for key: NativeChargePolicyPreferenceKey) throws -> Any?
    func setValues(_ preferences: NativeChargePolicyPreferences) throws
    func synchronize() throws
}

/// Injectable agent operations; production performs no discovery by mutation.
protocol NativeChargePolicyClient {
    var isAvailable: Bool { get }
    func reloadPreferences() throws
    func clearRegisteredLimit() throws
    func calibrationOverride() -> Bool?
}

/// Injectable output of the fixed, read-only pmset query.
protocol NativeChargePolicyLimitReader {
    func output() throws -> String
}

/// Errors retain failed/ambiguous operations for the caller's recovery policy.
public enum NativeChargePolicyError: Error, Equatable, LocalizedError {
    case rootRequired, unavailable, invalidPreferences, inconsistentPreferences, invalidLimit
    case synchronizationFailed, verificationFailed, appleOverride
    case nativeCall(Int32), invalidRegisteredLimits, processFailed, processTimedOut

    public var errorDescription: String? {
        switch self {
        case .rootRequired: return "La politique native de charge nécessite l’assistant système."
        case .unavailable: return "L’interface de la politique native de charge n’est pas disponible."
        case .invalidLimit: return "La cible native de charge est invalide."
        case .invalidPreferences, .inconsistentPreferences: return "L’état de la politique native est inconnu ou a changé."
        case .synchronizationFailed, .verificationFailed: return "La politique native n’a pas confirmé ses préférences."
        case .appleOverride: return "macOS effectue ou prépare un étalonnage de la batterie."
        case .nativeCall(let code): return "La politique native n’a pas confirmé l’opération (code \(code))."
        case .invalidRegisteredLimits: return "Les limites enregistrées par macOS sont inconnues ou incohérentes."
        case .processFailed, .processTimedOut: return "La lecture des limites enregistrées par macOS a échoué."
        }
    }
}

/// Owns preference writes only. The caller must save its durable recovery record
/// before calling apply or clearing the agent's registration.
public final class SystemNativeChargePolicyDriver: NativeChargePolicyDriver {
    private let store: any NativeChargePolicyPreferenceStore
    private let client: any NativeChargePolicyClient
    private let reader: any NativeChargePolicyLimitReader

    /// Creates the fixed root preference store and read-only system query.
    public convenience init() {
        self.init(store: RootNativeChargePolicyPreferenceStore(), client: SystemNativeChargePolicyClient(),
                  reader: SystemNativeChargePolicyLimitReader())
    }

    /// Injects side effects for tests without access to root preferences or hardware.
    init(store: any NativeChargePolicyPreferenceStore, client: any NativeChargePolicyClient,
         reader: any NativeChargePolicyLimitReader) {
        self.store = store; self.client = client; self.reader = reader
    }

    /// Checks the client and release ABI without changing preferences or charge state.
    public var isAvailable: Bool { client.isAvailable }

    public func readPreferences() throws -> NativeChargePolicyPreferences {
        guard isAvailable else { throw NativeChargePolicyError.unavailable }
        let first = try readPair()
        guard first == (try readPair()) else { throw NativeChargePolicyError.inconsistentPreferences }
        return first
    }

    private func readPair() throws -> NativeChargePolicyPreferences {
        let feature = try Self.preferenceValue(store.value(for: .featureState))
        let limit = try Self.preferenceValue(store.value(for: .limit))
        let result = NativeChargePolicyPreferences(featureState: feature, limit: limit)
        guard result.isValid else { throw NativeChargePolicyError.invalidPreferences }
        return result
    }

    /// Accepts property-list integers and Booleans without coercing strings or floats.
    static func preferenceValue(_ raw: Any?) throws -> NativeChargePolicyPreferenceValue {
        guard let raw else { return .absent }
        guard let number = raw as? NSNumber else { throw NativeChargePolicyError.invalidPreferences }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
        let encoding = String(cString: number.objCType)
        guard ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"].contains(encoding),
              let integer = Int(number.stringValue) else { throw NativeChargePolicyError.invalidPreferences }
        return .integer(integer)
    }

    public func apply(limit: Int) throws {
        guard (1...100).contains(limit) else { throw NativeChargePolicyError.invalidLimit }
        _ = try readPreferences()
        try write(.init(featureState: .integer(1), limit: .integer(limit)))
    }

    public func clearRegisteredLimit() throws {
        guard isAvailable else { throw NativeChargePolicyError.unavailable }
        guard calibrationOverride() == false else { throw NativeChargePolicyError.appleOverride }
        try client.clearRegisteredLimit()
    }

    public func restorePreferences(_ snapshot: NativeChargePolicyPreferences) throws {
        guard snapshot.isValid else { throw NativeChargePolicyError.invalidPreferences }
        guard isAvailable else { throw NativeChargePolicyError.unavailable }
        do {
            if try readPreferences() == snapshot { return }
        } catch NativeChargePolicyError.invalidPreferences {
            // A failed partial write may make the current pair invalid.
        }
        // The current keys may be a partial result of our failed write. Only
        // the owned, validated recovery snapshot decides what to put back.
        try write(snapshot)
    }

    private func write(_ preferences: NativeChargePolicyPreferences) throws {
        guard calibrationOverride() == false else { throw NativeChargePolicyError.appleOverride }
        try store.setValues(preferences)
        try store.synchronize()
        try client.reloadPreferences()
        guard try readPreferences() == preferences else { throw NativeChargePolicyError.verificationFailed }
        guard calibrationOverride() == false else { throw NativeChargePolicyError.appleOverride }
    }

    public func registeredLimit() throws -> Int? { try Self.registeredLimit(in: reader.output()) }
    public func calibrationOverride() -> Bool? { client.calibrationOverride() }

    /// Parses pmset's complete property-list response; unknown output is an error.
    static func registeredLimit(in output: String) throws -> Int? {
        guard output.utf8.count <= 65_536 else { throw NativeChargePolicyError.invalidRegisteredLimits }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "No battery level limits set" { return nil }
        let header = "Battery level limits:"
        guard text.hasPrefix(header), let data = text.dropFirst(header.count).data(using: .utf8),
              let entries = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            throw NativeChargePolicyError.invalidRegisteredLimits
        }
        if entries.isEmpty { return nil }
        // OpenStep property-list parsing otherwise silently keeps the last
        // occurrence of a duplicate dictionary key.
        let keys = try NSRegularExpression(pattern: #"\bchargeSocLimitSoc\s*="#)
        guard keys.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) == entries.count else {
            throw NativeChargePolicyError.invalidRegisteredLimits
        }
        var target: Int?
        for entry in entries {
            guard let value = entry["chargeSocLimitSoc"] as? String,
                  !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let limit = Int(value), (1...100).contains(limit), target == nil || target == limit else {
                throw NativeChargePolicyError.invalidRegisteredLimits
            }
            target = limit
        }
        return target
    }
}

/// Uses root's current-user/any-host domain, never the interactive user's defaults.
private struct RootNativeChargePolicyPreferenceStore: NativeChargePolicyPreferenceStore {
    private let domain = "com.apple.smartcharging.topoffprotection" as CFString
    private func requireRoot() throws { guard geteuid() == 0 else { throw NativeChargePolicyError.rootRequired } }
    func value(for key: NativeChargePolicyPreferenceKey) throws -> Any? {
        try requireRoot()
        return CFPreferencesCopyValue(key.rawValue as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func setValues(_ preferences: NativeChargePolicyPreferences) throws {
        try requireRoot()
        var values: [String: Any] = [:]
        var removed: [String] = []
        for (key, value) in [(NativeChargePolicyPreferenceKey.featureState, preferences.featureState), (.limit, preferences.limit)] {
            switch value {
            case .absent: removed.append(key.rawValue)
            case .integer(let number): values[key.rawValue] = NSNumber(value: number)
            case .boolean(let flag): values[key.rawValue] = flag ? kCFBooleanTrue : kCFBooleanFalse
            }
        }
        CFPreferencesSetMultiple(values as CFDictionary, removed as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func synchronize() throws {
        try requireRoot()
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw NativeChargePolicyError.synchronizationFailed
        }
    }
}

/// Wraps the checked C ABI and a fixed Darwin notification.
private struct SystemNativeChargePolicyClient: NativeChargePolicyClient {
    var isAvailable: Bool { maccare_powerui_policy_is_available() == 1 }
    func reloadPreferences() throws {
        let result = maccare_powerui_policy_preferences_changed()
        guard result == 0 else { throw NativeChargePolicyError.nativeCall(result) }
    }
    func clearRegisteredLimit() throws {
        let result = maccare_powerui_clear_limit()
        guard result == 0 else { throw NativeChargePolicyError.nativeCall(result) }
    }
    func calibrationOverride() -> Bool? {
        let result = maccare_powerui_calibration_override()
        return result < 0 ? nil : result != 0
    }
}

/// Runs only `/usr/bin/pmset -g battlimit`, with bounded duration and output.
private struct SystemNativeChargePolicyLimitReader: NativeChargePolicyLimitReader {
    func output() throws -> String {
        let process = Process(), pipe = Pipe(), exited = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { _ in exited.signal() }
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        do { try process.run() } catch { throw NativeChargePolicyError.processFailed }
        try? pipe.fileHandleForWriting.close()
        if exited.wait(timeout: .now() + 2) == .timedOut {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.2)
            }
            throw NativeChargePolicyError.processTimedOut
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw NativeChargePolicyError.processFailed }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 4_096), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 65_536 else { throw NativeChargePolicyError.processFailed }
        }
        guard let output = String(data: data, encoding: .utf8) else { throw NativeChargePolicyError.processFailed }
        return output
    }
}

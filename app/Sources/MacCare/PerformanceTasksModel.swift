import AppKit
import Foundation
import MacCareMaintenance
import SwiftUI

@MainActor
final class PerformanceTasksModel: ObservableObject {
    @Published var selection: Set<PerformanceTask> = []
    @Published private(set) var running: PerformanceTask?
    @Published private(set) var preparing = false
    @Published private(set) var reports: [PerformanceTask: MaintenanceReport] = [:]
    @Published private(set) var cachePlan: PurgeableCachePlan?
    @Published private(set) var cacheError: String?
    @Published private(set) var purgeableEstimateBytes: UInt64?
    @Published private(set) var lastSummary: String?
    private let defaults: UserDefaults
    private let executeSnapshots: @MainActor () async throws -> MaintenanceReport
    init(defaults: UserDefaults = .standard,
         executeSnapshots: @escaping @MainActor () async throws -> MaintenanceReport = { try await HelperClient.maintenance(.purgeable) }) {
        self.defaults = defaults
        self.executeSnapshots = executeSnapshots
    }
    private var operation: Task<Void, Never>?
    var isBusy: Bool { running != nil || preparing }
    var chosen: [PerformanceTask] { PerformanceTask.allCases.filter { selection.contains($0) } }

    func refresh(exclusions: [String]) {
        guard !isBusy else { return }
        preparing = true
        cachePlan = nil
        cacheError = nil
        let allowed = PurgeableCacheService.closedApplicationIDs()
        operation = Task {
            let result = await Task.detached(priority: .utility) {
                Result { try PurgeableCacheService.prepare(allowedIDs: allowed, exclusions: exclusions) }
            }.value
            switch result {
            case .success(let plan): cachePlan = plan
            case .failure(let error): cacheError = error.localizedDescription
            }
            purgeableEstimateBytes = await Task.detached(priority: .utility) {
                let values = try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(
                    forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
                guard let free = values?.volumeAvailableCapacity,
                      let important = values?.volumeAvailableCapacityForImportantUsage else { return nil as UInt64? }
                return UInt64(max(0, important - Int64(free)))
            }.value
            preparing = false
        }
    }

    /// Reçoit la liste exacte confirmée dans la feuille, indépendante des modifications de sélection.
    func run(_ tasks: [PerformanceTask], includeLocalSnapshots: Bool = false) {
        guard !isBusy, !tasks.isEmpty else { return }
        let plan = cachePlan
        running = tasks[0]
        lastSummary = nil
        operation = Task {
            var completed = 0
            for task in tasks {
                running = task
                let report: MaintenanceReport
                if task == .purgeable {
                    var snapshotReport: MaintenanceReport?
                    if PerformancePreferences.allowsLocalSnapshots(confirmed: includeLocalSnapshots, defaults: defaults) {
                        do { snapshotReport = try await executeSnapshots() }
                        catch { snapshotReport = .init(.failed, error.localizedDescription) }
                    }
                    let cacheReport: MaintenanceReport?
                    if let plan, !plan.items.isEmpty {
                        let allowed = PurgeableCacheService.closedApplicationIDs()
                        cacheReport = await Task.detached(priority: .userInitiated) {
                            PurgeableCacheService.execute(plan, allowedIDs: allowed)
                        }.value
                        cachePlan = nil
                    } else if let cacheError {
                        cacheReport = .init(.failed, "Caches : \(cacheError)")
                    } else { cacheReport = nil }
                    report = PurgeableMaintenanceReport.combine(snapshots: snapshotReport, caches: cacheReport)
                } else if task.requiresHelper {
                    do { report = try await HelperClient.maintenance(task) }
                    catch { report = .init(.failed, error.localizedDescription) }
                } else if task == .mail {
                    report = await Task.detached(priority: .userInitiated) {
                        MailIndexMaintenance.compact(home: FileManager.default.homeDirectoryForCurrentUser) {
                            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
                        }
                    }.value
                } else {
                    report = .init(.failed, "Tâche non prise en charge.")
                }
                reports[task] = report
                if report.succeeded { completed += 1 }
                selection.remove(task)
                if #available(macOS 14, *) {
                    AccessibilityNotification.Announcement("\(task.title) : \(report.message)").post()
                }
            }
            lastSummary = "\(completed) tâche(s) sur \(tasks.count) exécutée(s) ou lancée(s). Consultez le résultat de chaque tâche."
            running = nil
        }
    }
}

import XCTest
import ServiceManagement
import MacCareBattery
@testable import MacCare

@MainActor
final class BatteryModelSafetyTests: XCTestCase {
    private final class Client: BatteryClient {
        var status: SMAppService.Status = .enabled
        var failNext = false
        var rootActive = false
        var preparation: (() async -> Void)?
        var rootSession: UUID?
        var calls: [(BatteryCommand, UUID)] = []
        func snapshot() async -> BatterySnapshot { .init(percent: 80, onAC: true, temperature: 30) }
        func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
            calls.append((command, sessionID))
            if command == .enable { rootActive = true; rootSession = sessionID }
            if failNext { failNext = false; throw Failure() }
            if command == .disable { rootActive = false }
            return .init(snapshot: await snapshot(), supported: true, active: rootActive,
                         configuration: rootActive ? .init() : nil, ownedByCaller: rootSession == sessionID)
        }
        func prepareProtection() async throws { await preparation?() }
        func register() throws {}
        func openApproval() {}
    }
    private struct Failure: Error {}
    private func fixture(_ client: Client) -> (BatteryModel, UserDefaults, String) {
        let suite = testPreferencesSuite("MacCareBatteryAudit")
        let defaults = UserDefaults(suiteName: suite)!
        return (.init(defaults: defaults, monitor: false, client: client), defaults, suite)
    }
    func testLostEnableReplyDoesNotRenewAnUnconfirmedSession() async {
        let client = Client()
        let (model, defaults, suite) = fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        client.failNext = true
        await model.perform(.enable)
        XCTAssertNil(model.protection); XCTAssertNotNil(model.error)
        XCTAssertTrue(client.rootActive, "The request may have executed even though its reply was lost")
        await model.refresh(force: true)
        await model.refresh(force: true)
        XCTAssertEqual(client.calls.map(\.0), [.enable, .status, .status])
    }
    func testFailedDisableNeverKeepsRenewingCachedProtection() async {
        let client = Client()
        let (model, defaults, suite) = fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.perform(.enable)
        XCTAssertTrue(model.active)
        client.failNext = true
        await model.perform(.disable)
        XCTAssertNil(model.protection)
        await model.refresh(force: true)
        XCTAssertEqual(client.calls.map(\.0), [.enable, .disable, .status])
    }
    func testGracefulTerminationRestoresBeforeQuitAndKeepsSameSession() async {
        let client = Client()
        let (model, defaults, suite) = fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.perform(.enable)
        await model.refresh(force: true)
        await model.prepareForTermination()
        XCTAssertEqual(client.calls.map(\.0), [.enable, .heartbeat, .disable])
        XCTAssertEqual(Set(client.calls.map(\.1)).count, 1)
        XCTAssertFalse(model.active); XCTAssertFalse(client.rootActive)
    }
    func testQuitWhilePreparingPreventsLateActivation() async {
        let client = Client()
        let (model, defaults, suite) = fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = expectation(description: "preparation started")
        var release: CheckedContinuation<Void, Never>?
        client.preparation = {
            await withCheckedContinuation { release = $0; started.fulfill() }
        }
        let activation = Task { await model.perform(.enable) }
        await fulfillment(of: [started], timeout: 1)
        let ending = expectation(description: "termination started")
        let observation = model.$isTerminating.first(where: { $0 }).sink { _ in ending.fulfill() }
        defer { observation.cancel() }
        let termination = Task { await model.prepareForTermination() }
        await fulfillment(of: [ending], timeout: 1)
        release?.resume()
        await activation.value; await termination.value
        XCTAssertFalse(client.rootActive)
        XCTAssertFalse(client.calls.contains { $0.0 == .enable })
    }
    func testFreshAppNeverAdoptsOrRenewsAnotherInstance() async {
        let client = Client(); client.rootActive = true; client.rootSession = UUID()
        let (model, defaults, suite) = fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.refresh(force: true)
        XCTAssertEqual(client.calls.map(\.0), [.status, .status])
        XCTAssertFalse(model.protection?.ownedByCaller ?? true)
    }
}

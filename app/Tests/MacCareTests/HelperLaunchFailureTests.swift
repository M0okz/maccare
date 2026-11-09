import Testing
@testable import MacCare

struct HelperLaunchFailureTests {
    private static let observed = """
    system/org.maccare.helper = {
        state = spawn scheduled
        program identifier = Contents/MacOS/MacCareHelper (mode: 2)
        parent bundle identifier = org.maccare.app
        environment = {
            MACCARE_BATTERY_RECOVERY => 1
        }
        last exit code = 78: EX_CONFIG
        job state = spawn failed
    }
    """

    @Test func theObservedConfigurationFailureCanBeRepaired() {
        #expect(HelperLaunchFailure.isConfirmed(in: Self.observed))
    }
    @Test(arguments: [
        "pid = 1234", "job state = running", "last exit code = 1", "MACCARE_BATTERY_RECOVERY => 0",
        "parent bundle identifier = another.app", "program identifier = another-helper (mode: 2)"
    ])
    func anAmbiguousOrRunningServiceCannotBeRepaired(_ replacement: String) {
        let original: String
        if replacement.hasPrefix("pid") {
            #expect(!HelperLaunchFailure.isConfirmed(in: Self.observed.replacingOccurrences(of: "state = spawn scheduled", with: replacement)))
            return
        } else if replacement.hasPrefix("job state") { original = "job state = spawn failed" }
        else if replacement.hasPrefix("last exit") { original = "last exit code = 78: EX_CONFIG" }
        else if replacement.hasPrefix("MACCARE") { original = "MACCARE_BATTERY_RECOVERY => 1" }
        else if replacement.hasPrefix("parent") { original = "parent bundle identifier = org.maccare.app" }
        else { original = "program identifier = Contents/MacOS/MacCareHelper (mode: 2)" }
        #expect(!HelperLaunchFailure.isConfirmed(in: Self.observed.replacingOccurrences(of: original, with: replacement)))
    }
    @Test(arguments: ["", "error", "system/other.helper = {", String(repeating: "x", count: 32_769)])
    func missingOrUnrecognizedOutputFailsClosed(_ output: String) {
        #expect(!HelperLaunchFailure.isConfirmed(in: output))
    }
}

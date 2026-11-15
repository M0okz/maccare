import Foundation
import Testing
@testable import MacCare

struct SystemToolsTests {
    @Test func commandCanFillStandardErrorBeforeWritingStandardOutput() {
        // The fixture's alarm bounds the old pipe deadlock; it must finish before that alarm.
        let result = SystemTools.run("/usr/bin/perl", ["-e", "alarm 5; print STDERR 'e' x 262144; print STDOUT 'completed';"])
        #expect(result.ok)
        #expect(result.stdout == "completed")
        #expect(result.stderr.count == 262_144)
    }

    @Test func commandKeepsBothStreamsAndFailureStatus() {
        let result = SystemTools.run("/usr/bin/perl", ["-e", "print STDOUT 'result'; print STDERR 'diagnostic'; exit 7;"])
        #expect(result.status == 7)
        #expect(result.stdout == "result")
        #expect(result.stderr == "diagnostic")
    }
}

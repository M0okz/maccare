import Foundation
import MachO
import Testing
@testable import MacCare

struct ExecutableArchitecturesTests {
    @Test(arguments: [
        (UInt32(CPU_TYPE_ARM64), UInt32(0), true, false, "arm64"),
        (UInt32(CPU_TYPE_ARM64), UInt32(2), true, false, "arm64"),
        (UInt32(CPU_TYPE_X86_64), UInt32(3), true, false, "x86_64"),
        (UInt32(CPU_TYPE_X86_64), UInt32(8), true, false, "x86_64"),
        (UInt32(CPU_TYPE_X86), UInt32(3), false, false, "i386"),
        (UInt32(CPU_TYPE_ARM), UInt32(9), false, false, "arm"),
        (UInt32(CPU_TYPE_POWERPC), UInt32(0), false, true, "ppc"),
        (UInt32(CPU_TYPE_POWERPC64), UInt32(0), true, true, "ppc64")
    ])
    func readsCPUFamiliesWithoutLoadingTheExecutable(cpu: UInt32, subtype: UInt32, is64: Bool, bigEndian: Bool, expected: String) throws {
        try withFile(thin(cpu: cpu, subtype: subtype, is64: is64, bigEndian: bigEndian)) { url in
            #expect(ExecutableArchitectures.read(at: url) == [expected])
        }
    }

    @Test(arguments: [false, true])
    func readsUniversalMachOBothTableFormats(fat64: Bool) throws {
        let arm = thin(cpu: UInt32(CPU_TYPE_ARM64)), intel = thin(cpu: UInt32(CPU_TYPE_X86_64), subtype: 3)
        var data = Data()
        append32(fat64 ? 0xcafebabf : 0xcafebabe, to: &data, bigEndian: true)
        append32(2, to: &data, bigEndian: true)
        for (cpu, subtype, offset, size) in [(UInt32(CPU_TYPE_ARM64), UInt32(0), 4096, arm.count), (UInt32(CPU_TYPE_X86_64), UInt32(3), 8192, intel.count)] {
            append32(cpu, to: &data, bigEndian: true); append32(subtype, to: &data, bigEndian: true)
            if fat64 {
                append64(UInt64(offset), to: &data); append64(UInt64(size), to: &data)
            } else {
                append32(UInt32(offset), to: &data, bigEndian: true); append32(UInt32(size), to: &data, bigEndian: true)
            }
            append32(12, to: &data, bigEndian: true)
            if fat64 { append32(0, to: &data, bigEndian: true) }
        }
        data.append(Data(repeating: 0, count: 4096 - data.count)); data.append(arm)
        data.append(Data(repeating: 0, count: 8192 - data.count)); data.append(intel)
        try withFile(data) { url in #expect(ExecutableArchitectures.read(at: url) == ["arm64", "x86_64"]) }
    }

    @Test(arguments: [Data(), Data([0xcf, 0xfa]), Data("#!/bin/sh\nexit 0\n".utf8), Data("not an executable".utf8)])
    func unavailableArchitectureNeverBecomesAnUnsupportedArchitecture(data: Data) throws {
        try withFile(data) { url in #expect(ExecutableArchitectures.read(at: url) == nil) }
    }

    @Test func missingAndRemoteFilesRemainUnknown() {
        #expect(ExecutableArchitectures.read(at: URL(fileURLWithPath: "/nonexistent/" + UUID().uuidString)) == nil)
        #expect(ExecutableArchitectures.read(at: URL(string: "https://example.invalid/app")!) == nil)
    }

    @Test func unknownCPUFamilyRemainsUnknown() throws {
        try withFile(thin(cpu: 0x0100_7fff)) { url in #expect(ExecutableArchitectures.read(at: url) == nil) }
    }

    @Test func familyNormalizationDoesNotRejectAWorkingSubtype() {
        for (family, variant) in [("arm64", "arm64e"), ("x86_64", "x86_64h")] {
            #expect(ApplicationInsightPolicy.incompatibility(architectures: [family], minimum: "16", perArchitecture: [variant: "13"], system: "15.1", appleSilicon: true) == nil)
            #expect(ApplicationInsightPolicy.incompatibility(architectures: [family], minimum: nil, perArchitecture: [family: "16", variant: "13"], system: "15.1", appleSilicon: true) == nil)
            #expect(ApplicationInsightPolicy.incompatibility(architectures: [family], minimum: nil, perArchitecture: [family: "16", variant: "17"], system: "15.1", appleSilicon: true) != nil)
        }
    }

    @Test(arguments: Array(0..<10))
    func malformedUniversal64TablesRemainUnknown(kind: Int) throws {
        var data = Data()
        append32(0xcafebabf, to: &data, bigEndian: true)
        append32(1, to: &data, bigEndian: true)
        append32(UInt32(CPU_TYPE_ARM64), to: &data, bigEndian: true)
        append32(0, to: &data, bigEndian: true)
        append64(40, to: &data); append64(32, to: &data)
        append32(0, to: &data, bigEndian: true); append32(0, to: &data, bigEndian: true)
        data.append(thin(cpu: UInt32(CPU_TYPE_ARM64)))
        try withFile(data) { url in #expect(ExecutableArchitectures.read(at: url) == ["arm64"]) }
        switch kind {
        case 0: replace32(0, in: &data, at: 4)
        case 1: replace32(UInt32.max, in: &data, at: 4)
        case 2: replace64(UInt64.max, in: &data, at: 16)
        case 3: replace64(UInt64.max, in: &data, at: 24)
        case 4: replace64(0, in: &data, at: 16)
        case 5: replace32(UInt32(CPU_TYPE_X86_64), in: &data, at: 8)
        case 6: data.removeLast()
        case 7: data.replaceSubrange(40..<44, with: [0, 0, 0, 0])
        case 8: data = Data(data.prefix(8))
        default: replace64(28, in: &data, at: 24)
        }
        try withFile(data) { url in #expect(ExecutableArchitectures.read(at: url) == nil) }
    }

    @Test func readsByteSwappedUniversal64Table() throws {
        var data = Data()
        for word in [UInt32(0xcafebabf), 1, UInt32(CPU_TYPE_ARM64), 0] {
            append32(word, to: &data, bigEndian: false)
        }
        for value in [UInt64(40), 32] {
            var encoded = value.littleEndian
            withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
        }
        append32(0, to: &data, bigEndian: false); append32(0, to: &data, bigEndian: false)
        data.append(thin(cpu: UInt32(CPU_TYPE_ARM64)))
        try withFile(data) { url in #expect(ExecutableArchitectures.read(at: url) == ["arm64"]) }
    }

    @Test func updateValidationAcceptsSupportedFamiliesWithoutACommand() throws {
        try withFile(thin(cpu: UInt32(CPU_TYPE_X86_64), subtype: 8)) { url in
            try ApplicationUpdateArchive.validateArchitecture(at: url)
        }
        #if arch(arm64)
        try withFile(thin(cpu: UInt32(CPU_TYPE_ARM64), subtype: 2)) { url in
            try ApplicationUpdateArchive.validateArchitecture(at: url)
        }
        #endif
    }

    @Test func updateValidationRefusesUnknownAndUnsupportedPayloads() throws {
        for data in [Data("not an executable".utf8), thin(cpu: UInt32(CPU_TYPE_POWERPC))] {
            try withFile(data) { url in
                #expect(throws: ApplicationUpdateFailure.self) {
                    try ApplicationUpdateArchive.validateArchitecture(at: url)
                }
            }
        }
    }

    private func replace32(_ value: UInt32, in data: inout Data, at offset: Int) {
        var bytes = Data(); append32(value, to: &bytes, bigEndian: true)
        data.replaceSubrange(offset..<(offset + 4), with: bytes)
    }
    private func replace64(_ value: UInt64, in data: inout Data, at offset: Int) {
        var bytes = Data(); append64(value, to: &bytes)
        data.replaceSubrange(offset..<(offset + 8), with: bytes)
    }

    private func thin(cpu: UInt32, subtype: UInt32 = 0, is64: Bool = true, bigEndian: Bool = false) -> Data {
        var data = Data()
        let words: [UInt32] = [is64 ? 0xfeedfacf : 0xfeedface, cpu, subtype, 2, 0, 0, 0] + (is64 ? [0] : [])
        for word in words { append32(word, to: &data, bigEndian: bigEndian) }
        if data.count < 32 { data.append(Data(repeating: 0, count: 32 - data.count)) }
        return data
    }
    private func append32(_ value: UInt32, to data: inout Data, bigEndian: Bool) {
        var encoded = bigEndian ? value.bigEndian : value.littleEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
    private func append64(_ value: UInt64, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
    private func withFile(_ data: Data, check: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacCare-ArchitectureTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fixture")
        try data.write(to: url)
        try check(url)
    }
}

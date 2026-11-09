import Foundation
import CoreFoundation
import MachO

/// Reads Mach-O CPU families in-process; never launches an executable.
enum ExecutableArchitectures {
    /// Returns nil for missing, unreadable, non-Mach-O or unknown CPU formats.
    /// CoreFoundation reports CPU families, so arm64e and x86_64h are normalized.
    static func read(at executableURL: URL) -> Set<String>? {
        guard executableURL.isFileURL else { return nil }
        let nativeValues = (CFBundleCopyExecutableArchitecturesForURL(executableURL as CFURL) as? [NSNumber])
            .flatMap { $0.isEmpty ? nil : $0.map(\.uint32Value) }
        guard let values = nativeValues ?? universal64CPUs(at: executableURL), !values.isEmpty else { return nil }
        var families = Set<String>()
        for value in values {
            switch value {
            case UInt32(CPU_TYPE_ARM64): families.insert("arm64")
            case UInt32(CPU_TYPE_X86_64): families.insert("x86_64")
            case UInt32(CPU_TYPE_X86): families.insert("i386")
            case UInt32(CPU_TYPE_ARM): families.insert("arm")
            case UInt32(CPU_TYPE_POWERPC): families.insert("ppc")
            case UInt32(CPU_TYPE_POWERPC64): families.insert("ppc64")
            default: return nil
            }
        }
        return families
    }

    /// CoreFoundation does not recognize every FAT64 table. Read only its bounded
    /// headers and verify that each CPU entry describes an in-bounds Mach-O slice.
    private static func universal64CPUs(at url: URL) -> [UInt32]? {
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let length = try file.seekToEnd()
            try file.seek(toOffset: 0)
            guard let header = try file.read(upToCount: 8), header.count == 8 else { return nil }
            let magic = unsigned(header, at: 0, count: 4, bigEndian: true)
            guard magic == UInt64(FAT_MAGIC_64) || magic == UInt64(FAT_CIGAM_64) else { return nil }
            let bigEndian = magic == UInt64(FAT_MAGIC_64)
            guard let count = unsigned(header, at: 4, count: 4, bigEndian: bigEndian),
                  (1...64).contains(count), 8 + count * 32 <= length,
                  let table = try file.read(upToCount: Int(count) * 32), table.count == Int(count) * 32 else { return nil }
            var cpus: [UInt32] = []
            for index in 0..<Int(count) {
                let entry = index * 32
                guard let cpu = unsigned(table, at: entry, count: 4, bigEndian: bigEndian),
                      let offset = unsigned(table, at: entry + 8, count: 8, bigEndian: bigEndian),
                      let size = unsigned(table, at: entry + 16, count: 8, bigEndian: bigEndian),
                      offset >= 8 + count * 32, offset <= length, size >= 28, size <= length - offset else { return nil }
                try file.seek(toOffset: offset)
                guard let slice = try file.read(upToCount: Int(min(size, 32))),
                      let sliceMagic = unsigned(slice, at: 0, count: 4, bigEndian: true) else { return nil }
                let sliceBigEndian: Bool
                switch sliceMagic {
                case UInt64(MH_MAGIC): sliceBigEndian = true
                case UInt64(MH_CIGAM): sliceBigEndian = false
                case UInt64(MH_MAGIC_64):
                    guard slice.count >= 32 else { return nil }
                    sliceBigEndian = true
                case UInt64(MH_CIGAM_64):
                    guard slice.count >= 32 else { return nil }
                    sliceBigEndian = false
                default: return nil
                }
                guard unsigned(slice, at: 4, count: 4, bigEndian: sliceBigEndian) == cpu else { return nil }
                cpus.append(UInt32(cpu))
            }
            return cpus
        } catch { return nil }
    }

    /// Decode small integers without aligned loads or unchecked file offsets.
    private static func unsigned(_ data: Data, at offset: Int, count: Int, bigEndian: Bool) -> UInt64? {
        guard count > 0, count <= 8, offset >= 0, data.count >= count, offset <= data.count - count else { return nil }
        let bytes = data[offset..<(offset + count)]
        return (bigEndian ? Array(bytes) : Array(bytes.reversed())).reduce(0) { ($0 << 8) | UInt64($1) }
    }

}

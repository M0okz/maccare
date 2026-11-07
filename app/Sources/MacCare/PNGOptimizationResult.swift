import Foundation

struct PNGOptimizationResult: Decodable, Sendable {
    let original_bytes: UInt64
    let optimized_bytes: UInt64
    let output_path: String?
    var savedBytes: UInt64 { original_bytes > optimized_bytes ? original_bytes - optimized_bytes : 0 }
}

import XCTest
@testable import MacCare

final class FilesManagerTests: XCTestCase {
    func testScopeRejectsSiblingLibraryHiddenAndPackageRoots() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        XCTAssertTrue(FileSearchScope.isAllowed(home))
        XCTAssertTrue(FileSearchScope.isAllowed(home.appendingPathComponent("Documents/QA")))
        for path in [home.path + "-other", home.path + "/Library/Caches", home.path + "/.ssh", home.path + "/Documents/QA.app/Contents", "/System"] {
            XCTAssertFalse(FileSearchScope.isAllowed(URL(fileURLWithPath: path)), path)
        }
    }

    func testBothSearchesStayInsideExplicitFolderAndIgnoreSymlink() throws {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("MacCare-QA-ScopedSearch-\(UUID().uuidString)")
        let selected = base.appendingPathComponent("Selected")
        let other = base.appendingPathComponent("Outside")
        try fm.createDirectory(at: selected, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let content = Data(repeating: 37, count: 1_048_600)
        for name in ["original.dat", "copy.dat"] { try content.write(to: selected.appendingPathComponent(name)) }
        let outside = other.appendingPathComponent("outside.dat")
        try content.write(to: outside)
        try fm.createSymbolicLink(at: selected.appendingPathComponent("linked.dat"), withDestinationURL: outside)
        let large = try Engine.findLargeFiles(minBytes: 1_000_000, root: selected.path)
        XCTAssertEqual(large.root, selected.path)
        XCTAssertEqual(Set(large.files?.map(\.path) ?? []), Set(["original.dat", "copy.dat"].map { selected.appendingPathComponent($0).path }))
        let duplicates = try Engine.findDuplicates(root: selected.path)
        XCTAssertEqual(duplicates.root, selected.path)
        XCTAssertEqual(duplicates.groups?.count, 1)
        XCTAssertEqual(Set(duplicates.groups?.first?.files.map(\.path) ?? []), Set(large.files?.map(\.path) ?? []))
        let decisions = try Engine.planUserFiles(root: selected.path, files: [LargeFile(path: outside.path, size_bytes: UInt64(content.count), modified: 0, identity: FileIdentity(device: 0, inode: 0))])
        XCTAssertFalse(decisions.contains { $0.allowed })
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
    }

    @MainActor func testKeepingACopyRemovesItFromRemovalSelection() {
        let identity = FileIdentity(device: 1, inode: 1)
        let first = DupFile(path: "/QA/original.png", size_bytes: 100, modified: 1, identity: identity)
        let copy = DupFile(path: "/QA/copy.png", size_bytes: 100, modified: 2, identity: identity)
        let group = DupGroup(length: 100, files: [first, copy])
        let model = DuplicatesModel()
        model.toggle(first, in: group)
        XCTAssertTrue(model.selection.isEmpty)
        model.toggle(copy, in: group)
        XCTAssertEqual(model.selection, [copy.path])
        model.keep(copy, in: group)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.isKept(copy, in: group))
        model.toggle(first, in: group)
        model.retainSelection(in: [])
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testSearchAndSortDoNotChangeCandidatesOrSelection() {
        let identity = FileIdentity(device: 1, inode: 1)
        let files = [LargeFile(path: "/QA/Zebra.mov", size_bytes: 200, modified: 10, identity: identity),
                     LargeFile(path: "/QA/Alpha.png", size_bytes: 100, modified: 20, identity: identity)]
        XCTAssertEqual(FileManagerPresentation.files(files, query: "PNG", sort: .size).map(\.path), ["/QA/Alpha.png"])
        XCTAssertEqual(FileManagerPresentation.files(files, query: "", sort: .name).map(\.path), ["/QA/Alpha.png", "/QA/Zebra.mov"])
        XCTAssertEqual(FileManagerPresentation.files(files, query: "", sort: .date).first?.path, "/QA/Zebra.mov")
        XCTAssertEqual(files.count, 2)
    }
}

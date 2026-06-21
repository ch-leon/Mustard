import XCTest
@testable import MustardKit

final class AreaRouterTests: XCTestCase {
    // "Digital Licence" → sub-vault "DL" (reverse of MeetingTaskSync.defaultAreaMap).
    func test_derivesFromWorkRoot_whenNoMatchingSource() {
        let dir = AreaRouter.workingDirectory(
            forArea: "Digital Licence", sources: [], workVaultRoot: "/Users/leon/Codeheroes work")
        XCTAssertEqual(dir, "/Users/leon/Codeheroes work/DL")
    }

    func test_prefersConfiguredSource_byProjectFolder() {
        let sources = [SourceConfig(id: .vault, project: "DL", enabled: true,
                                    workingDirectory: "/custom/DL-kb")]
        let dir = AreaRouter.workingDirectory(
            forArea: "Digital Licence", sources: sources, workVaultRoot: "/Users/leon/Codeheroes work")
        XCTAssertEqual(dir, "/custom/DL-kb")
    }

    func test_unknownArea_returnsNil() {
        XCTAssertNil(AreaRouter.workingDirectory(
            forArea: "Personal Errands", sources: [], workVaultRoot: "/Users/leon/Codeheroes work"))
    }

    func test_noWorkRootAndNoSource_returnsNil() {
        XCTAssertNil(AreaRouter.workingDirectory(
            forArea: "Digital Licence", sources: [], workVaultRoot: ""))
    }

    func test_nilArea_returnsNil() {
        XCTAssertNil(AreaRouter.workingDirectory(
            forArea: nil, sources: [], workVaultRoot: "/Users/leon/Codeheroes work"))
    }
}

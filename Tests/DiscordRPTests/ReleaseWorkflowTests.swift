import XCTest

final class ReleaseWorkflowTests: XCTestCase {
    func testManualReleaseUsesResolvedInputTagInsteadOfDispatchRefName() throws {
        let workflow = try String(
            contentsOfFile: ".github/workflows/release.yml",
            encoding: .utf8
        )

        XCTAssertTrue(workflow.contains("RELEASE_TAG: ${{ inputs.tag || github.ref_name }}"))
        XCTAssertTrue(workflow.contains("ref: ${{ env.RELEASE_TAG }}"))
        XCTAssertTrue(workflow.contains(#"TAG="${RELEASE_TAG#v}""#))
        XCTAssertTrue(workflow.contains(#"gh release create "$RELEASE_TAG""#))
        XCTAssertFalse(workflow.contains("GITHUB_REF_NAME"))
    }
}

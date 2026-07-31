import Foundation
import XCTest

@testable import ClearCore

final class PathSafetyPolicyTests: XCTestCase {
    func testStrictDescendantUsesPathComponentsInsteadOfStringPrefix() {
        let root = URL(fileURLWithPath: "/Users/test/Library/Caches/app")

        XCTAssertTrue(
            PathSafetyPolicy.isStrictDescendant(
                URL(fileURLWithPath: "/Users/test/Library/Caches/app/data"),
                of: root
            )
        )
        XCTAssertFalse(
            PathSafetyPolicy.isStrictDescendant(
                URL(fileURLWithPath: "/Users/test/Library/Caches/app-evil/data"),
                of: root
            )
        )
        XCTAssertFalse(PathSafetyPolicy.isStrictDescendant(root, of: root))
    }

    func testDefaultRulesNeverUseBroadLibraryRoots() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let rules = DefaultCleanRules.make(homeDirectory: home)
        let expectedRoots: Set<URL> = [
            "Library/Caches/com.google.Chrome",
            "Library/Caches/com.microsoft.VSCode",
            "Library/Caches/com.tinyspeck.slackmacgap",
            "Library/Caches/com.spotify.client",
            "Library/Caches/com.hnc.Discord",
            "Library/Caches/us.zoom.xos",
            "Library/Logs/DiagnosticReports"
        ].map {
            home.appendingPathComponent($0, isDirectory: true)
                .standardizedFileURL
        }.reduce(into: Set<URL>()) { $0.insert($1) }

        let actualRoots = Set(rules.map(\.rootURL))
        let uniqueKeys = Set(rules.map { "\($0.id):\($0.version)" })

        XCTAssertEqual(actualRoots, expectedRoots)
        XCTAssertEqual(uniqueKeys.count, rules.count)
        XCTAssertEqual(rules.count, 7)
        XCTAssertTrue(rules.allSatisfy(\.rootURL.isFileURL))
        XCTAssertTrue(
            rules.allSatisfy {
                PathSafetyPolicy.isStrictDescendant(
                    $0.rootURL,
                    of: home
                )
            }
        )
    }

    func testTraversalSyntaxCannotEscapeExpectedRoot() {
        let root = URL(
            fileURLWithPath: "/Users/test/Library/Caches/app",
            isDirectory: true
        )
        let escaped = root
            .appendingPathComponent("../Documents/private.txt")
            .standardizedFileURL

        XCTAssertFalse(
            PathSafetyPolicy.isStrictDescendant(escaped, of: root)
        )
    }
}

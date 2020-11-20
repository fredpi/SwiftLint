import Foundation
@testable import SwiftLintFramework
import XCTest

extension ConfigurationTests {
    // MARK: - Methods: Tests
    func testValidChildConfig() {
        for path in [Mock.Dir.childConfigTest1, Mock.Dir.childConfigTest2] {
            FileManager.default.changeCurrentDirectoryPath(path)

            assertEqualExceptForFileGraph(
                Configuration(configurationFiles: ["child_config_main.yml"]),
                Configuration(configurationFiles: ["child_config_expected.yml"])
            )
        }
    }

    func testValidParentConfig() {
        for path in [Mock.Dir.parentConfigTest1, Mock.Dir.parentConfigTest2] {
            FileManager.default.changeCurrentDirectoryPath(path)

            assertEqualExceptForFileGraph(
                Configuration(configurationFiles: ["parent_config_main.yml"]),
                Configuration(configurationFiles: ["parent_config_expected.yml"])
            )
        }
    }

    func testCommandLineChildConfigs() {
        for path in [Mock.Dir.childConfigTest1, Mock.Dir.childConfigTest2] {
            FileManager.default.changeCurrentDirectoryPath(path)

            assertEqualExceptForFileGraph(
                Configuration(
                    configurationFiles: ["child_config_main.yml", "child_config_child1.yml", "child_config_child2.yml"]
                ),
                Configuration(configurationFiles: ["child_config_expected.yml"])
            )
        }
    }

    // MARK: Helpers
    /// This helper function checks whether two configurations are equal except for their file graph.
    /// This is needed to test a child/parent merged config against an expected config.
    func assertEqualExceptForFileGraph(_ configuration1: Configuration, _ configuration2: Configuration) {
        XCTAssertEqual(
            configuration1.rulesWrapper.disabledRuleIdentifiers,
            configuration2.rulesWrapper.disabledRuleIdentifiers
        )

        XCTAssertEqual(
            configuration1.rules.map { type(of: $0).description.identifier },
            configuration2.rules.map { type(of: $0).description.identifier }
        )

        XCTAssertEqual(
            Set(configuration1.rulesWrapper.allRulesWrapped.map { $0.rule.configurationDescription }),
            Set(configuration2.rulesWrapper.allRulesWrapped.map { $0.rule.configurationDescription })
        )

        XCTAssertEqual(
            Set(configuration1.includedPaths),
            Set(configuration2.includedPaths)
        )

        XCTAssertEqual(
            Set(configuration1.excludedPaths),
            Set(configuration2.excludedPaths)
        )
    }
}

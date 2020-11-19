import Foundation
@testable import SwiftLintFramework
import XCTest

extension ConfigurationTests {
    func testValidRemoteChildConfig() {
        FileManager.default.changeCurrentDirectoryPath(projectMockPathRemoteChildConfig)

        assertEqualExceptForFileGraph(
            Configuration(
                configurationFiles: ["child_config_main.yml"],
                mockedNetworkResults: [
                    "https://www.mock.com":
                    """
                    included:
                      - Test/Test1/Test/Test
                      - Test/Test2/Test/Test
                    """
                ]
            ),
            Configuration(configurationFiles: ["child_config_expected.yml"])
        )
    }

    func testValidRemoteParentConfig() {
        FileManager.default.changeCurrentDirectoryPath(projectMockPathRemoteParentConfig)

        assertEqualExceptForFileGraph(
            Configuration(
                configurationFiles: ["parent_config_main.yml"],
                mockedNetworkResults: [
                    "https://www.mock.com":
                    """
                    included:
                      - Test/Test1
                      - Test/Test2

                    excluded:
                      - Test/Test1/Test
                      - Test/Test2/Test

                    line_length: 80
                    """
                ]
            ),
            Configuration(configurationFiles: ["parent_config_expected.yml"])
        )
    }
}

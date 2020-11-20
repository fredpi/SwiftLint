@testable import SwiftLintFramework
import XCTest

private extension Configuration {
    func contains<T: Rule>(rule: T.Type) -> Bool {
        return rules.contains { $0 is T }
    }
}

extension ConfigurationTests {
    // MARK: - Rules Merging
    func testMerge() {
        let config0Merge2 = Mock.Config._0.merged(withChild: Mock.Config._2, rootDirectory: "")

        XCTAssertFalse(Mock.Config._0.contains(rule: ForceCastRule.self))
        XCTAssertTrue(Mock.Config._2.contains(rule: ForceCastRule.self))
        XCTAssertFalse(config0Merge2.contains(rule: ForceCastRule.self))

        XCTAssertTrue(Mock.Config._0.contains(rule: TodoRule.self))
        XCTAssertTrue(Mock.Config._2.contains(rule: TodoRule.self))
        XCTAssertTrue(config0Merge2.contains(rule: TodoRule.self))

        XCTAssertFalse(Mock.Config._3.contains(rule: TodoRule.self))
        XCTAssertFalse(
            config0Merge2.merged(withChild: Mock.Config._3, rootDirectory: "").contains(rule: TodoRule.self)
        )
    }

    // MARK: - Merging Aspects
    func testWarningThresholdMerging() {
        func configuration(forWarningThreshold warningThreshold: Int?) -> Configuration {
            return Configuration(
                ruleList: primaryRuleList,
                warningThreshold: warningThreshold,
                reporter: XcodeReporter.identifier
            )
        }
        XCTAssertEqual(configuration(forWarningThreshold: 3)
            .merged(withChild: configuration(forWarningThreshold: 2), rootDirectory: "").warningThreshold,
                       2)
        XCTAssertEqual(configuration(forWarningThreshold: nil)
            .merged(withChild: configuration(forWarningThreshold: 2), rootDirectory: "").warningThreshold,
                       2)
        XCTAssertEqual(configuration(forWarningThreshold: 3)
            .merged(withChild: configuration(forWarningThreshold: nil), rootDirectory: "").warningThreshold,
                       3)
        XCTAssertNil(configuration(forWarningThreshold: nil)
            .merged(withChild: configuration(forWarningThreshold: nil), rootDirectory: "").warningThreshold)
    }

    func testOnlyRulesMerging() {
        let baseConfiguration = Configuration(rulesMode: .default(disabled: [],
                                                                  optIn: [ForceTryRule.description.identifier,
                                                                          ForceCastRule.description.identifier]))
        let onlyConfiguration = Configuration(rulesMode: .only([TodoRule.description.identifier]))
        XCTAssertTrue(baseConfiguration.contains(rule: TodoRule.self))
        XCTAssertEqual(onlyConfiguration.rules.count, 1)
        XCTAssertTrue(onlyConfiguration.rules[0] is TodoRule)

        let mergedConfiguration1 = baseConfiguration.merged(withChild: onlyConfiguration, rootDirectory: "")
        XCTAssertEqual(mergedConfiguration1.rules.count, 1)
        XCTAssertTrue(mergedConfiguration1.rules[0] is TodoRule)

        // Also test the other way around
        let mergedConfiguration2 = onlyConfiguration.merged(withChild: baseConfiguration, rootDirectory: "")
        XCTAssertEqual(mergedConfiguration2.rules.count, 3) // 2 opt-ins + 1 from the only rules
        XCTAssertTrue(mergedConfiguration2.contains(rule: TodoRule.self))
        XCTAssertTrue(mergedConfiguration2.contains(rule: ForceCastRule.self))
        XCTAssertTrue(mergedConfiguration2.contains(rule: ForceTryRule.self))
    }

    func testCustomRulesMerging() {
        let mergedConfiguration = Mock.Config._0CustomRules.merged(
            withChild: Mock.Config._2CustomRules,
            rootDirectory: ""
        )
        guard let mergedCustomRules = mergedConfiguration.rules.first(where: { $0 is CustomRules }) as? CustomRules
            else {
            return XCTFail("Custom rule are expected to be present")
        }
        XCTAssertTrue(
            mergedCustomRules.configuration.customRuleConfigurations.contains(where: { $0.identifier == "no_abc" })
        )
        XCTAssertTrue(
            mergedCustomRules.configuration.customRuleConfigurations.contains(where: { $0.identifier == "no_abcd" })
        )
    }

    func testMergingAllowsDisablingParentsCustomRules() {
        let mergedConfiguration = Mock.Config._0CustomRules.merged(
            withChild: Mock.Config._2CustomRulesDisabled,
            rootDirectory: ""
        )
        guard let mergedCustomRules = mergedConfiguration.rules.first(where: { $0 is CustomRules }) as? CustomRules
            else {
            return XCTFail("Custom rule are expected to be present")
        }
        XCTAssertFalse(
            mergedCustomRules.configuration.customRuleConfigurations.contains(where: { $0.identifier == "no_abc" })
        )
        XCTAssertTrue(
            mergedCustomRules.configuration.customRuleConfigurations.contains(where: { $0.identifier == "no_abcd" })
        )
    }

    // MARK: - Nested Configurations
    func testLevel0() {
        XCTAssertEqual(Mock.Config._0.configuration(for: SwiftLintFile(path: Mock.Swift._0)!),
                       Mock.Config._0)
    }

    func testLevel1() {
        XCTAssertEqual(Mock.Config._0.configuration(for: SwiftLintFile(path: Mock.Swift._1)!),
                       Mock.Config._0)
    }

    func testLevel2() {
        let config = Mock.Config._0.configuration(for: SwiftLintFile(path: Mock.Swift._2)!)
        var config2 = Mock.Config._2
        config2.fileGraph = Configuration.FileGraph(rootDirectory: Mock.Dir.level2)

        XCTAssertEqual(
            config,
            Mock.Config._0.merged(withChild: config2, rootDirectory: config.rootDirectory)
        )
    }

    func testLevel3() {
        let config = Mock.Config._0.configuration(for: SwiftLintFile(path: Mock.Swift._3)!)
        var config3 = Mock.Config._3
        config3.fileGraph = Configuration.FileGraph(rootDirectory: Mock.Dir.level3)

        XCTAssertEqual(
            config,
            Mock.Config._0.merged(withChild: config3, rootDirectory: config.rootDirectory)
        )
    }

    func testNestedConfigurationForOnePathPassedIn() {
        let config = Configuration(configurationFiles: [Mock.Yml._0])
        XCTAssertEqual(
            config.configuration(for: SwiftLintFile(path: Mock.Swift._3)!),
            config
        )
    }

    func testParentConfigIsIgnoredAsNestedConfiguration() {
        // If a configuration has already been used to build the main config,
        // it should not again be regarded as a nested config
        XCTAssertEqual(
            Mock.Config.nested.configuration(for: SwiftLintFile(path: Mock.Swift.nestedSub)!),
            Mock.Config.nested
        )
    }
}

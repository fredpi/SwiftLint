@testable import SwiftLintFramework

protocol ProjectMock {
    var testResourcesPath: String { get }
}

extension ProjectMock {
    // MARK: Directory Paths
    var projectMockPathLevel0: String {
        testResourcesPath.stringByAppendingPathComponent("ProjectMock")
    }

    var projectMockPathLevel1: String {
        projectMockPathLevel0.stringByAppendingPathComponent("Level1")
    }

    var projectMockPathLevel2: String {
        projectMockPathLevel1.stringByAppendingPathComponent("Level2")
    }

    var projectMockPathLevel3: String {
        projectMockPathLevel2.stringByAppendingPathComponent("Level3")
    }

    var projectMockNestedPath: String {
        projectMockPathLevel0.stringByAppendingPathComponent("NestedConfig/Test")
    }

    var projectMockNestedSubPath: String {
        projectMockNestedPath.stringByAppendingPathComponent("Sub")
    }

    var projectMockPathChildConfigValid1: String {
        projectMockPathLevel0.stringByAppendingPathComponent("ChildConfig/Valid1/Main")
    }

    var projectMockPathChildConfigValid2: String {
        projectMockPathLevel0.stringByAppendingPathComponent("ChildConfig/Valid2")
    }

    var projectMockPathParentConfigValid1: String {
        projectMockPathLevel0.stringByAppendingPathComponent("ParentConfig/Valid1")
    }

    var projectMockPathParentConfigValid2: String {
        projectMockPathLevel0.stringByAppendingPathComponent("ParentConfig/Valid2")
    }

    var projectMockEmptyFolder: String {
        projectMockPathLevel0.stringByAppendingPathComponent("EmptyFolder")
    }

    // MARK: YAML Paths
    var projectMockYAML0: String {
        projectMockPathLevel0.stringByAppendingPathComponent(Configuration.defaultFileName)
    }

    var projectMockYAML0CustomPath: String {
        projectMockPathLevel0.stringByAppendingPathComponent("custom.yml")
    }

    var projectMockYAML0CustomRules: String {
        projectMockPathLevel0.stringByAppendingPathComponent("custom_rules.yml")
    }

    var projectMockYAML2: String {
        projectMockPathLevel2.stringByAppendingPathComponent(Configuration.defaultFileName)
    }

    var projectMockYAML2CustomRules: String {
        projectMockPathLevel2.stringByAppendingPathComponent("custom_rules.yml")
    }

    var projectMockYAML2CustomRulesDisabled: String {
        projectMockPathLevel2.stringByAppendingPathComponent("custom_rules_disabled.yml")
    }

    // MARK: Swift File Paths
    var projectMockSwift0: String {
        projectMockPathLevel0.stringByAppendingPathComponent("Level0.swift")
    }

    var projectMockSwift1: String {
        projectMockPathLevel1.stringByAppendingPathComponent("Level1.swift")
    }

    var projectMockSwift2: String {
        projectMockPathLevel2.stringByAppendingPathComponent("Level2.swift")
    }

    var projectMockSwift3: String {
        projectMockPathLevel3.stringByAppendingPathComponent("Level3.swift")
    }

    var projectMockNestedSubSwift: String {
        projectMockNestedSubPath.stringByAppendingPathComponent("Sub.swift")
    }

    var projectMockNestedYAML: String {
        projectMockNestedPath.stringByAppendingPathComponent(Configuration.defaultFileName)
    }

    var projectMockConfig0: Configuration {
        Configuration(configurationFiles: [])
    }

    var projectMockConfig0CustomPath: Configuration {
        Configuration(configurationFiles: [projectMockYAML0CustomPath])
    }

    var projectMockConfig0CustomRules: Configuration {
        Configuration(configurationFiles: [projectMockYAML0CustomRules])
    }

    var projectMockConfig2: Configuration {
        Configuration(configurationFiles: [projectMockYAML2])
    }

    var projectMockConfig2CustomRules: Configuration {
        Configuration(configurationFiles: [projectMockYAML2CustomRules])
    }

    var projectMockConfig2CustomRulesDisabled: Configuration {
        Configuration(configurationFiles: [projectMockYAML2CustomRulesDisabled])
    }

    var projectMockConfig3: Configuration {
        Configuration(configurationFiles: [projectMockPathLevel3 + "/" + Configuration.defaultFileName])
    }

    var projectMockNestedConfig: Configuration {
        Configuration(configurationFiles: [projectMockNestedYAML])
    }
}

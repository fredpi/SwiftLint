import Foundation
import SourceKittenFramework

extension Configuration {
    public func configuration(for file: File) -> Configuration {
        if let containingDir = file.path?.bridge().deletingLastPathComponent {
            return configuration(forPath: containingDir)
        }
        return self
    }

    private func configuration(forPath path: String) -> Configuration {
        if path == rootDirectory {
            return self
        }

        let pathNSString = path.bridge()
        let configurationSearchPath = pathNSString.appendingPathComponent(Configuration.fileName)

        // If a configuration exists and it isn't us, load and merge the configurations
        if configurationSearchPath != configurationPath &&
            FileManager.default.fileExists(atPath: configurationSearchPath) {
            let fullPath = pathNSString.absolutePathRepresentation()
            let config = Configuration.getCached(atPath: fullPath) ??
                Configuration(
                    path: configurationSearchPath,
                    rootPath: fullPath,
                    optional: false,
                    quiet: true
                )
            return merged(with: config)
        }

        // If we are not at the root path, continue down the tree
        if path != rootPath && path != "/" {
            return configuration(forPath: pathNSString.deletingLastPathComponent)
        }

        // If nothing else, return self
        return self
    }

    private var rootDirectory: String? {
        guard let rootPath = rootPath else {
            return nil
        }

        var isDirectoryObjC: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectoryObjC) else {
            return nil
        }

        if isDirectoryObjC.boolValue {
            return rootPath
        } else {
            return rootPath.bridge().deletingLastPathComponent
        }
    }

    private struct HashableRule: Hashable {
        fileprivate let rule: Rule

        fileprivate static func == (lhs: HashableRule, rhs: HashableRule) -> Bool {
            // Don't use `isEqualTo` in case its internal implementation changes from
            // using the identifier to something else, which could mess up with the `Set`
            return type(of: lhs.rule).description.identifier == type(of: rhs.rule).description.identifier
        }

        fileprivate func hash(into hasher: inout Hasher) {
            hasher.combine(type(of: rule).description.identifier)
        }
    }

    private func mergeCustomRules(in rules: inout [Rule], rulesMode: RulesMode, parent: RulesWrapper, sub: RulesWrapper) {
        guard
            let thisCustomRules = (parent.configuredRules.first { $0 is CustomRules }) as? CustomRules,
            let otherCustomRules = (sub.configuredRules.first { $0 is CustomRules }) as? CustomRules
            else { return } // TODO: Handle properly

        let customRulesFilter: (RegexConfiguration) -> (Bool)
        switch rulesMode {
        case .allEnabled:
            customRulesFilter = { _ in true }

        case let .whitelisted(whitelistedRules):
            customRulesFilter = { whitelistedRules.contains($0.identifier) }

        case let .default(disabledRules, _):
            customRulesFilter = { !disabledRules.contains($0.identifier) }
        }

        var customRules = CustomRules()
        var configuration = CustomRulesConfiguration()

        configuration.customRuleConfigurations = Set(
            thisCustomRules.configuration.customRuleConfigurations
        ).union(
            Set(otherCustomRules.configuration.customRuleConfigurations)
        ).filter(customRulesFilter)
        customRules.configuration = configuration

        rules = rules.filter { !($0 is CustomRules) } + [customRules]
    }

    private func mergingRules(with configuration: Configuration) -> [Rule] {
        let regularMergedRules: [Rule]
        switch configuration.rulesWrapper.rulesMode {
        case .allEnabled:
            // Technically not possible yet as it's not configurable in a .swiftlint.yml file,
            // but implemented for completeness
            regularMergedRules = configuration.rules
        case .whitelisted(let whitelistedRules):
            // Use an intermediate set to filter out duplicate rules when merging configurations
            // (always use the nested rule first if it exists)
            regularMergedRules = Set(configuration.rules.map(HashableRule.init))
                .union(rules.map(HashableRule.init))
                .map { $0.rule }
                .filter { rule in
                    return whitelistedRules.contains(type(of: rule).description.identifier)
                }
        case let .default(disabled, optIn):
            // Same here
            regularMergedRules = Set(
                configuration.rules
                    // Enable rules that are opt-in by the child configuration
                    .filter { rule in
                        return optIn.contains(type(of: rule).description.identifier)
                    }
                    .map(HashableRule.init)
                )
                // And disable rules that are disabled by the child configuration
                .union(
                    rules.filter { rule in
                        return !disabled.contains(type(of: rule).description.identifier)
                    }.map(HashableRule.init)
                )
                .map { $0.rule }
        }
        return regularMergedRules
    }

    func mergedRulesWrapper(with configuration: Configuration) -> RulesWrapper {
        guard rulesWrapper.ruleList == configuration.rulesWrapper.ruleList else {
            // As the base ruleList differs, we just return the child config
            return configuration.rulesWrapper
        }

        let ruleList = rulesWrapper.ruleList
        let newRulesMode: RulesMode
        var newConfiguredRules: [Rule]

        // Placeholder values TODO
        newRulesMode = .allEnabled
        newConfiguredRules = []
        // Placeholder values

        switch rulesWrapper.rulesMode {
        case let .default(disabled, optIn):
            guard case let .default(subDisabled, subOptIn) = configuration.rulesWrapper.rulesMode else {
                // As the rule modes differ, we just return the child config
                return configuration.rulesWrapper
            }

            print(disabled, subDisabled, optIn, subOptIn)

        case let .whitelisted(whitelisted):
            guard case let .whitelisted(subWhitelisted) = configuration.rulesWrapper.rulesMode else {
                // As the rule modes differ, we just return the child config
                return configuration.rulesWrapper
            }

            print(whitelisted, subWhitelisted)

        case .allEnabled:
            guard case .allEnabled = configuration.rulesWrapper.rulesMode else {
                // As the rule modes differ, we just return the child config
                return configuration.rulesWrapper
            }
        }

        mergeCustomRules(
            in: &newConfiguredRules, rulesMode: newRulesMode, parent: rulesWrapper, sub: configuration.rulesWrapper
        )
        guard let rulesWrapper = RulesWrapper(
            ruleList: ruleList,
            configuredRules: newConfiguredRules,
            rulesMode: newRulesMode
        ) else { exit(0) } // TODO: Handle properly

        return rulesWrapper
    }

    func mergedIncludedAndExcluded(with configuration: Configuration) -> (included: [String], excluded: [String]) {
        if rootDirectory != configuration.rootDirectory {
            // Configurations aren't on same level => use child configuration
            return (included: configuration.included, excluded: configuration.excluded)
        }

        // Prefer child configuration over parent configuration
        return (
            included: included.filter { !configuration.excluded.contains($0) } + configuration.included,
            excluded: excluded.filter { !configuration.included.contains($0) } + configuration.excluded
        )
    }

    internal func merged(with configuration: Configuration) -> Configuration {
        let includedAndExcluded = mergedIncludedAndExcluded(with: configuration)

        return Configuration(
            rulesWrapper: mergedRulesWrapper(with: configuration),
            included: includedAndExcluded.included,
            excluded: includedAndExcluded.excluded,
            // The minimum warning threshold if both exist, otherwise the nested,
            // and if it doesn't exist try to use the parent one
            warningThreshold: warningThreshold.map { warningThreshold in
                return min(configuration.warningThreshold ?? .max, warningThreshold)
            } ?? configuration.warningThreshold,
            reporter: reporter, // Always use the parent reporter
            cachePath: cachePath, // Always use the parent cache path
            rootPath: configuration.rootPath,
            indentation: configuration.indentation
        )
    }
}

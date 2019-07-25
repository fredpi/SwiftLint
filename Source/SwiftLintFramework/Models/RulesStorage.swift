import Foundation

public class RulesStorage {
    // MARK: - Subtypes
    public enum Mode {
        case `default`(disabled: Set<String>, optIn: Set<String>)
        case whitelisted(Set<String>)
        case allEnabled

        init?(
            enableAllRules: Bool,
            whitelistRules: [String],
            optInRules: [String],
            disabledRules: [String],
            analyzerRules: [String]
        ) {
            func warnAboutDuplicates(in identifiers: [String]) {
                if Set(identifiers).count != identifiers.count {
                    let duplicateRules = identifiers.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
                        .filter { $0.1 > 1 }
                    queuedPrintError(
                        duplicateRules
                            .map { rule in "warning: '\(rule.0)' is listed \(rule.1) times" }
                            .joined(separator: "\n")
                    )
                }
            }

            if enableAllRules {
                self = .allEnabled
            } else if !whitelistRules.isEmpty {
                if !disabledRules.isEmpty || !optInRules.isEmpty {
                    queuedPrintError("'\(Configuration.Key.disabledRules.rawValue)' or " +
                        "'\(Configuration.Key.optInRules.rawValue)' cannot be used in combination " +
                        "with '\(Configuration.Key.whitelistRules.rawValue)'")
                    return nil
                }

                warnAboutDuplicates(in: whitelistRules + analyzerRules)
                self = .whitelisted(Set(whitelistRules + analyzerRules))
            } else {
                warnAboutDuplicates(in: disabledRules)
                warnAboutDuplicates(in: optInRules + analyzerRules)
                self = .default(disabled: Set(disabledRules), optIn: Set(optInRules + analyzerRules))
            }
        }

        func applied(aliasResolver: (String) -> String, validRuleIdentifiers: ([String]) -> [String]) -> Mode {
            switch self {
            case let .default(disabled, optIn):
                return .default(
                    disabled: Set(validRuleIdentifiers(disabled.map(aliasResolver))),
                    optIn: Set(validRuleIdentifiers(optIn.map(aliasResolver)))
                )

            case let .whitelisted(whitelisted):
                return .whitelisted(Set(validRuleIdentifiers(whitelisted.map(aliasResolver))))

            case .allEnabled:
                return .allEnabled
            }
        }
    }

    fileprivate struct HashableRuleWrapper: Hashable {
        fileprivate let rule: Rule

        fileprivate static func == (lhs: HashableRuleWrapper, rhs: HashableRuleWrapper) -> Bool {
            // Only use identifier for equality check (not taking config into account)
            return type(of: lhs.rule).description.identifier == type(of: rhs.rule).description.identifier
        }

        fileprivate func hash(into hasher: inout Hasher) {
            hasher.combine(type(of: rule).description.identifier)
        }
    }

    // MARK: - Properties
    public let allRulesWithConfigurations: [Rule]
    private let mode: Mode
    private let aliasResolver: (String) -> String

    /// All rules enabled in this configuration, derived from rule mode (whitelist / optIn - disabled) & existing rules
    public lazy var resultingRules: [Rule] = {
        var resultingRules = [Rule]()

        // Apply mode to allRulesWithConfigurations
        switch mode {
        case .allEnabled:
            resultingRules = allRulesWithConfigurations

        case let .whitelisted(whitelistedRuleIdentifiers):
            resultingRules = allRulesWithConfigurations.filter { rule in
                whitelistedRuleIdentifiers.contains(type(of: rule).description.identifier)
            }

        case let .default(disabledRuleIdentifiers, optInRuleIdentifiers):
            resultingRules = allRulesWithConfigurations.filter { rule in
                let id = type(of: rule).description.identifier
                if disabledRuleIdentifiers.contains(id) { return false }
                return optInRuleIdentifiers.contains(id) || !(rule is OptInRule)
            }
        }

        // Sort by name
        return resultingRules.sorted { type(of: $0).description.identifier < type(of: $1).description.identifier }
    }()

    public lazy var disabledRuleIdentifiers: [String] = {
        switch mode {
        case let .default(disabled, _):
            return disabled.sorted(by: <)

        case let .whitelisted(whitelisted):
            return allRulesWithConfigurations
                .map { type(of: $0).description.identifier }
                .filter { !whitelisted.contains($0) }
                .sorted(by: <)

        case .allEnabled:
            return []
        }
    }()

    // MARK: - Initializers
    init(mode: Mode, allRulesWithConfigurations: [Rule], aliasResolver: @escaping (String) -> String) {
        self.allRulesWithConfigurations = allRulesWithConfigurations
        self.aliasResolver = aliasResolver
        self.mode = mode.applied(
            aliasResolver: aliasResolver,
            validRuleIdentifiers: { ruleIdentifiers in
                // Fetch valid rule identifiers
                let regularRuleIdentifiers = allRulesWithConfigurations.map { type(of: $0).description.identifier }
                let configurationCustomRulesIdentifiers =
                    (allRulesWithConfigurations.first { $0 is CustomRules } as? CustomRules)?
                        .configuration.customRuleConfigurations.map { $0.identifier } ?? []
                let validRuleIdentifiers = regularRuleIdentifiers + configurationCustomRulesIdentifiers

                // Process invalid rule identifiers
                let invalidRuleIdentifiers = ruleIdentifiers.filter { !validRuleIdentifiers.contains($0) }
                if !invalidRuleIdentifiers.isEmpty {
                    for invalidRuleIdentifier in invalidRuleIdentifiers {
                        queuedPrintError(
                            "warning: '\(invalidRuleIdentifier)' is not a valid rule identifier"
                        )
                    }

                    queuedPrintError(
                        "Valid rule identifiers:\n\(validRuleIdentifiers.sorted().joined(separator: "\n"))"
                    )
                }

                // Return valid rule identifiers
                return ruleIdentifiers.filter(validRuleIdentifiers.contains)
            }
        )
    }

    // MARK: - Methods: Merging
    internal func merged(with sub: RulesStorage) -> RulesStorage {
        // Merge allRulesWithConfigurations
        let mainConfigSet = Set(allRulesWithConfigurations.map(HashableRuleWrapper.init))
        let subConfigSet = Set(sub.allRulesWithConfigurations.map(HashableRuleWrapper.init))
        let subConfigRulesWithConfig = subConfigSet.filter { $0.rule.initializedWithNonEmptyConfiguration }
        let rulesUniqueToSubConfig = subConfigSet.subtracting(mainConfigSet)
        let newAllRulesWithConfigurations = subConfigRulesWithConfig // Include, if rule is configured in sub
            .union(rulesUniqueToSubConfig) // Include, if rule is in sub config only
            .union(mainConfigSet) // Use configurations from parent for remaining rules
            .map { $0.rule }

        // Merge mode
        let newMode: Mode
        switch sub.mode {
        case let .default(subDisabled, subOptIn):
            switch mode {
            case let .default(disabled, optIn):
                // Only use parent disabled / optIn if sub config doesn't tell the opposite
                newMode = .default(
                    disabled: Set(subDisabled).union(Set(disabled.filter { !subOptIn.contains($0) }))
                        // (. != true) means (. == false) || (. == nil)
                        .filter { isOptInRule($0, allRulesWithConfigurations: newAllRulesWithConfigurations) != true },
                    optIn: Set(subOptIn).union(Set(optIn.filter { !subDisabled.contains($0) }))
                        // (. != false) means (. == true) || (. == nil)
                        .filter { isOptInRule($0, allRulesWithConfigurations: newAllRulesWithConfigurations) != false }
                )

            case let .whitelisted(whitelisted):
                // Allow parent whitelist rules that weren't disabled via the sub config & opt-ins from the sub config
                newMode = .whitelisted(Set(
                    subOptIn + whitelisted.filter { !subDisabled.contains($0) }
                ))

            case .allEnabled:
                // Opt-in to every rule that isn't disabled via sub config
                newMode = .default(
                    disabled: subDisabled
                        .filter { isOptInRule($0, allRulesWithConfigurations: newAllRulesWithConfigurations) == false },
                    optIn: Set(newAllRulesWithConfigurations.map { type(of: $0).description.identifier }
                        .filter {
                            !subDisabled.contains($0)
                                && isOptInRule($0, allRulesWithConfigurations: newAllRulesWithConfigurations) == true
                        }
                    )
                )
            }

        case let .whitelisted(subWhitelisted):
            // Always use the sub whitelist
            newMode = .whitelisted(subWhitelisted)

        case .allEnabled:
            // Always use .allEnabled mode
            newMode = .allEnabled
        }

        // Assemble & return merged RulesStorage
        return RulesStorage(
            mode: newMode,
            allRulesWithConfigurations: merged(customRules: newAllRulesWithConfigurations, mode: newMode, with: sub),
            aliasResolver: { sub.aliasResolver(self.aliasResolver($0)) }
        )
    }

    private func merged(customRules rules: [Rule], mode: Mode, with sub: RulesStorage) -> [Rule] {
        guard
            let customRulesRule = (allRulesWithConfigurations.first { $0 is CustomRules }) as? CustomRules,
            let subCustomRulesRule = (sub.allRulesWithConfigurations.first { $0 is CustomRules }) as? CustomRules
        else {
            // Merging is only needed if both parent & sub have a custom rules rule
            return rules
        }

        let customRulesFilter: (RegexConfiguration) -> (Bool)
        switch mode {
        case .allEnabled:
            customRulesFilter = { _ in true }

        case let .whitelisted(whitelistedRules):
            customRulesFilter = { whitelistedRules.contains($0.identifier) }

        case let .default(disabledRules, _):
            customRulesFilter = { !disabledRules.contains($0.identifier) }
        }

        var configuration = CustomRulesConfiguration()
        configuration.customRuleConfigurations = Set(customRulesRule.configuration.customRuleConfigurations)
            .union(Set(subCustomRulesRule.configuration.customRuleConfigurations))
            .filter(customRulesFilter)

        var customRules = CustomRules()
        customRules.configuration = configuration

        return rules.filter { !($0 is CustomRules) } + [customRules]
    }

    // MARK: Helpers
    static var isOptInRuleCache: [String: Bool] = [:]

    private func isOptInRule(_ identifier: String, allRulesWithConfigurations: [Rule]) -> Bool? {
        if let cachedIsOptInRule = RulesStorage.isOptInRuleCache[identifier] {
            return cachedIsOptInRule
        }

        let isOptInRule = allRulesWithConfigurations
            .first { type(of: $0).description.identifier == identifier } is OptInRule
        RulesStorage.isOptInRuleCache[identifier] = isOptInRule
        return isOptInRule
    }
}

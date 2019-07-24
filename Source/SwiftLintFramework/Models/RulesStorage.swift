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
                            .map { rule in "Configuration Warning: '\(rule.0)' is listed \(rule.1) times" }
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
    }

    fileprivate struct HashableRule: Hashable {
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

    // MARK: - Properties
    private let mode: Mode
    private let allRulesWithConfigurations: [Rule]
    private let aliasResolver: (String) -> String

    /// All rules enabled in this configuration, derived from rule mode (whitelist / optIn - disabled) & existing rules
    public lazy var resultingRules: [Rule] = {
        var resultingRules = [Rule]()

        // Fetch valid rule identifiers
        let regularRuleIdentifiers = allRulesWithConfigurations.map { type(of: $0).description.identifier }
        let configurationCustomRulesIdentifiers =
            (allRulesWithConfigurations.first { $0 is CustomRules } as? CustomRules)?
            .configuration.customRuleConfigurations.map { $0.identifier } ?? []
        let validRuleIdentifiers = regularRuleIdentifiers + configurationCustomRulesIdentifiers

        // Apply mode to allRulesWithConfigurations
        switch mode {
        case .allEnabled:
            resultingRules = allRulesWithConfigurations

        case let .whitelisted(whitelistedRuleIdentifiers):
            let validWhitelistedRuleIdentifiers = validateRuleIdentifiers(
                ruleIdentifiers: whitelistedRuleIdentifiers.map(aliasResolver),
                validRuleIdentifiers: validRuleIdentifiers
            )

            resultingRules = allRulesWithConfigurations.filter { rule in
                validWhitelistedRuleIdentifiers.contains(type(of: rule).description.identifier)
            }

        case let .default(disabledRuleIdentifiers, optInRuleIdentifiers):
            let validDisabledRuleIdentifiers = validateRuleIdentifiers(
                ruleIdentifiers: disabledRuleIdentifiers.map(aliasResolver),
                validRuleIdentifiers: validRuleIdentifiers
            )
            let validOptInRuleIdentifiers = validateRuleIdentifiers(
                ruleIdentifiers: optInRuleIdentifiers.map(aliasResolver),
                validRuleIdentifiers: validRuleIdentifiers
            )

            resultingRules = allRulesWithConfigurations.filter { rule in
                let id = type(of: rule).description.identifier
                if validDisabledRuleIdentifiers.contains(id) { return false }
                return validOptInRuleIdentifiers.contains(id) || !(rule is OptInRule)
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
        self.mode = mode
        self.allRulesWithConfigurations = allRulesWithConfigurations
        self.aliasResolver = aliasResolver
    }

    // MARK: - Methods
    /// Validate that all rule identifiers map to a defined rule and warn about duplicates
    private func validateRuleIdentifiers(ruleIdentifiers: [String], validRuleIdentifiers: [String]) -> [String] {
        let invalidRuleIdentifiers = ruleIdentifiers.filter { !validRuleIdentifiers.contains($0) }
        if !invalidRuleIdentifiers.isEmpty {
            for invalidRuleIdentifier in invalidRuleIdentifiers {
                queuedPrintError("Configuration Error: '\(invalidRuleIdentifier)' is not a valid rule identifier")
            }

            queuedPrintError("Valid rule identifiers:\n\(validRuleIdentifiers.sorted().joined(separator: "\n"))")
        }

        return ruleIdentifiers.filter(validRuleIdentifiers.contains)
    }

    // MARK: Merging
    func merged(with sub: RulesStorage) -> RulesStorage {
        // Merge allRulesWithConfigurations
        let newAllRulesWithConfigurations = Set(sub.allRulesWithConfigurations.map(HashableRule.init))
            .union(allRulesWithConfigurations.map(HashableRule.init))
            .map { $0.rule }

        // Merge mode
        let newMode: Mode
        switch sub.mode {
        case let .default(subDisabled, subOptIn):
            switch mode {
            case let .default(disabled, optIn):
                // Only use parent disabled / optIn if sub config doesn't tell the opposite
                newMode = .default(
                    disabled: Set(subDisabled).union(Set(disabled.filter { !subOptIn.contains($0) })),
                    optIn: Set(subOptIn).union(Set(optIn.filter { !subDisabled.contains($0) }))
                )

            case let .whitelisted(whitelisted):
                // Allow parent whitelist rules that weren't disabled via the sub config & opt-ins from the sub config
                newMode = .whitelisted(Set(
                    subOptIn + whitelisted.filter { !subDisabled.contains($0) }
                ))

            case .allEnabled:
                // Opt-in to every rule that isn't disabled via sub config
                newMode = .default(
                    disabled: subDisabled,
                    optIn: Set(newAllRulesWithConfigurations.map { type(of: $0).description.identifier }
                        .filter { $0 is OptInRule && !subDisabled.contains($0) })
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
}

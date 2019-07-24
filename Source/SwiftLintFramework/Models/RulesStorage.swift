import Foundation

public class RulesStorage {
    // MARK: - Subtypes
    public enum Mode {
        case `default`(disabled: [String], optIn: [String])
        case whitelisted([String])
        case allEnabled
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
    lazy var resultingRules: [Rule] = {
        let regularRuleIdentifiers = allRulesWithConfigurations.map { type(of: $0).description.identifier }
        let configurationCustomRulesIdentifiers =
            (allRulesWithConfigurations.first { $0 is CustomRules } as? CustomRules)?
            .configuration.customRuleConfigurations.map { $0.identifier } ?? []
        let validRuleIdentifiers = regularRuleIdentifiers + configurationCustomRulesIdentifiers

        switch mode {
        case .allEnabled:
            return allRulesWithConfigurations

        case let .whitelisted(whitelistedRuleIdentifiers):
            let validWhitelistedRuleIdentifiers = validateRuleIdentifiers(
                ruleIdentifiers: whitelistedRuleIdentifiers.map(aliasResolver),
                validRuleIdentifiers: validRuleIdentifiers
            )

            // Warn if a whitelist rule identifier is listed multiple times
            // Continue even if it's the case, as this is not a fatal error
            _ = containsDuplicateIdentifiers(validWhitelistedRuleIdentifiers)

            return allRulesWithConfigurations.filter { rule in
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

            // Warn if a disable / opt-in rule identifier is listed multiple times
            // Continue even if it's the case, as this is not a fatal error
            _ = containsDuplicateIdentifiers(validDisabledRuleIdentifiers)
            _ = containsDuplicateIdentifiers(validOptInRuleIdentifiers)

            return allRulesWithConfigurations.filter { rule in
                let id = type(of: rule).description.identifier
                if validDisabledRuleIdentifiers.contains(id) { return false }
                return validOptInRuleIdentifiers.contains(id) || !(rule is OptInRule)
            }
        }
    }()

    // MARK: - Initializers
    init(mode: Mode, allRulesWithConfigurations: [Rule], aliasResolver: @escaping (String) -> String) {
        self.mode = mode
        self.allRulesWithConfigurations = allRulesWithConfigurations
        self.aliasResolver = aliasResolver
    }

    // MARK: - Methods
    /// Validate that all rule identifiers map to a defined rule
    private func validateRuleIdentifiers(ruleIdentifiers: [String], validRuleIdentifiers: [String]) -> [String] {
        let invalidRuleIdentifiers = ruleIdentifiers.filter { !validRuleIdentifiers.contains($0) }
        if !invalidRuleIdentifiers.isEmpty {
            for invalidRuleIdentifier in invalidRuleIdentifiers {
                queuedPrintError("configuration error: '\(invalidRuleIdentifier)' is not a valid rule identifier")
            }
            let listOfValidRuleIdentifiers = validRuleIdentifiers.sorted().joined(separator: "\n")
            queuedPrintError("Valid rule identifiers:\n\(listOfValidRuleIdentifiers)")
        }

        return ruleIdentifiers.filter(validRuleIdentifiers.contains)
    }

    /// Validates that rule identifiers aren't listed multiple times
    private func containsDuplicateIdentifiers(_ identifiers: [String]) -> Bool {
        guard Set(identifiers).count != identifiers.count else { return false }

        let duplicateRules = identifiers.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .filter { $0.1 > 1 }
        queuedPrintError(
            duplicateRules.map { rule in
                "configuration error: '\(rule.0)' is listed \(rule.1) times"
            }.joined(separator: "\n")
        )

        return true
    }

    // MARK: Merging
    func merged(with sub: RulesStorage) -> RulesStorage {
        // Merge mode
        let newMode: Mode
        switch mode {
        case let .default(disabled, optIn):
            guard case let .default(subDisabled, subOptIn) = sub.mode else {
                // As the rule modes differ, we just return the child config
                return sub
            }

            // Only use parent disabled / optIn if sub config doesn't tell the opposite
            newMode = .default(
                disabled: Array(Set(subDisabled).union(Set(disabled.filter { !subOptIn.contains($0) }))),
                optIn: Array(Set(subOptIn).union(Set(optIn.filter { !subDisabled.contains($0) })))
            )

        case .whitelisted:
            guard case let .whitelisted(subWhitelisted) = sub.mode else {
                // As the rule modes differ, we just return the child config
                return sub
            }

            // Always use the sub whitelist
            newMode = .whitelisted(subWhitelisted)

        case .allEnabled:
            guard case .allEnabled = sub.mode else {
                // As the rule modes differ, we just return the child config
                return sub
            }

            // Stay in .allEnabled mode
            newMode = .allEnabled
        }

        // Merge allRulesWithConfigurations
        var newAllRulesWithConfigurations = Set(sub.allRulesWithConfigurations.map(HashableRule.init))
            .union(allRulesWithConfigurations.map(HashableRule.init))
            .map { $0.rule }
        mergeCustomRules(in: &newAllRulesWithConfigurations, mode: newMode, with: sub)

        // Assemble merged RulesStorage
        return RulesStorage(
            mode: newMode,
            allRulesWithConfigurations: allRulesWithConfigurations,
            aliasResolver: { self.aliasResolver(sub.aliasResolver($0)) }
        )
    }

    private func mergeCustomRules(in rules: inout [Rule], mode: Mode, with sub: RulesStorage) {
        guard
            let thisCustomRules = (resultingRules.first { $0 is CustomRules }) as? CustomRules,
            let otherCustomRules = (sub.resultingRules.first { $0 is CustomRules }) as? CustomRules
        else { return } // TODO: Handle properly

        let customRulesFilter: (RegexConfiguration) -> (Bool)
        switch mode {
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
}

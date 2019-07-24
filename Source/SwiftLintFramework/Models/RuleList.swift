public enum RuleListError: Error {
    case duplicatedConfigurations(rule: Rule.Type)
}

public struct RuleList {
    public let list: [String: Rule.Type]
    private let aliases: [String: String]

    public init(rules: Rule.Type...) {
        self.init(rules: rules)
    }

    public init(rules: [Rule.Type]) {
        var tmpList = [String: Rule.Type]()
        var tmpAliases = [String: String]()

        for rule in rules {
            let identifier = rule.description.identifier
            tmpList[identifier] = rule
            for alias in rule.description.deprecatedAliases {
                tmpAliases[alias] = identifier
            }
            tmpAliases[identifier] = identifier
        }
        list = tmpList
        aliases = tmpAliases
    }

    internal func configuredRules(with dictionary: [String: Any]) throws -> [Rule] {
        var rules = [String: Rule]()

        for (key, configuration) in dictionary {
            guard let identifier = identifier(for: key), let ruleType = list[identifier] else {
                continue
            }
            guard rules[identifier] == nil else {
                throw RuleListError.duplicatedConfigurations(rule: ruleType)
            }
            do {
                let configuredRule = try ruleType.init(configuration: configuration)
                rules[identifier] = configuredRule
            } catch {
                queuedPrintError("Invalid configuration for '\(identifier)'. Falling back to default.")
                rules[identifier] = ruleType.init()
            }
        }

        for (identifier, ruleType) in list where rules[identifier] == nil {
            rules[identifier] = ruleType.init()
        }

        return Array(rules.values)
    }

    internal func identifier(for alias: String) -> String? {
        return aliases[alias]
    }

    internal func allValidIdentifiers() -> [String] {
        return list.flatMap { _, rule -> [String] in
            rule.description.allIdentifiers
        }
    }
}

extension RuleList: Equatable {
    public static func == (lhs: RuleList, rhs: RuleList) -> Bool {
        return lhs.list.map { $0.0 } == rhs.list.map { $0.0 }
            && lhs.list.map { $0.1.description } == rhs.list.map { $0.1.description }
            && lhs.aliases == rhs.aliases
    }
}

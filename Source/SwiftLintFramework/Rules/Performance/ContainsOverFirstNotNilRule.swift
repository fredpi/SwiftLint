import SourceKittenFramework

public struct ContainsOverFirstNotNilRule: CallPairRule, OptInRule, ConfigurationProviderRule {
    public var configuration = SeverityConfiguration(.warning)
    public var initializedWithNonEmptyConfiguration: Bool = false

    public init() {}

    public static let description = RuleDescription(
        identifier: "contains_over_first_not_nil",
        name: "Contains over first not nil",
        description: "Prefer `contains` over `first(where:) != nil` and `firstIndex(where:) != nil`.",
        kind: .performance,
        nonTriggeringExamples: ["first", "firstIndex"].flatMap { method in
            return [
                "let \(method) = myList.\(method)(where: { $0 % 2 == 0 })\n",
                "let \(method) = myList.\(method) { $0 % 2 == 0 }\n"
            ]
        },
        triggeringExamples: ["first", "firstIndex"].flatMap { method in
            return [
                "↓myList.\(method) { $0 % 2 == 0 } != nil\n",
                "↓myList.\(method)(where: { $0 % 2 == 0 }) != nil\n",
                "↓myList.map { $0 + 1 }.\(method)(where: { $0 % 2 == 0 }) != nil\n",
                "↓myList.\(method)(where: someFunction) != nil\n",
                "↓myList.map { $0 + 1 }.\(method) { $0 % 2 == 0 } != nil\n",
                "(↓myList.\(method) { $0 % 2 == 0 }) != nil\n"
            ]
        }
    )

    public func validate(file: File) -> [StyleViolation] {
        let pattern = "[\\}\\)]\\s*!=\\s*nil"
        let firstViolations = validate(file: file, pattern: pattern, patternSyntaxKinds: [.keyword],
                                       callNameSuffix: ".first", severity: configuration.severity,
                                       reason: "Prefer `contains` over `first(where:) != nil`")
        let firstIndexViolations = validate(file: file, pattern: pattern, patternSyntaxKinds: [.keyword],
                                            callNameSuffix: ".firstIndex", severity: configuration.severity,
                                            reason: "Prefer `contains` over `firstIndex(where:) != nil`")

        return firstViolations + firstIndexViolations
    }
}

import SourceKittenFramework

public struct VerticalParameterAlignmentRule: ASTRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.warning)
    public var initializedWithNonEmptyConfiguration: Bool = false

    public init() {}

    public static let description = RuleDescription(
        identifier: "vertical_parameter_alignment",
        name: "Vertical Parameter Alignment",
        description: "Function parameters should be aligned vertically if they're in multiple lines in a declaration.",
        kind: .style,
        nonTriggeringExamples: VerticalParameterAlignmentRuleExamples.nonTriggeringExamples,
        triggeringExamples: VerticalParameterAlignmentRuleExamples.triggeringExamples
    )

    public func validate(file: File, kind: SwiftDeclarationKind,
                         dictionary: [String: SourceKitRepresentable]) -> [StyleViolation] {
        guard SwiftDeclarationKind.functionKinds.contains(kind),
            let startOffset = dictionary.nameOffset,
            let length = dictionary.nameLength,
            case let endOffset = startOffset + length else {
            return []
        }

        let params = dictionary.substructure.filter { subDict in
            return subDict.kind.flatMap(SwiftDeclarationKind.init) == .varParameter &&
                (subDict.offset ?? .max) < endOffset
        }

        guard params.count > 1 else {
            return []
        }

        let contents = file.contents.bridge()
        let calculateLocation = { (dict: [String: SourceKitRepresentable]) -> Location? in
            guard let byteOffset = dict.offset,
                let lineAndChar = contents.lineAndCharacter(forByteOffset: byteOffset) else {
                    return nil
            }

            return Location(file: file.path, line: lineAndChar.line, character: lineAndChar.character)
        }

        let paramLocations = params.compactMap { paramDict -> Location? in
            let paramLocation = calculateLocation(paramDict).map { [$0] } ?? []
            let attributesLocations = paramDict.swiftAttributes.compactMap(calculateLocation)

            return [paramLocation, attributesLocations].flatMap { $0 }.min()
        }

        return violations(for: paramLocations)
    }

    private func violations(for paramLocations: [Location]) -> [StyleViolation] {
        var violationLocations = [Location]()
        guard let firstParamLoc = paramLocations.first else { return [] }

        for (index, paramLoc) in paramLocations.enumerated() where index > 0 && paramLoc.line! > firstParamLoc.line! {
            let previousParamLoc = paramLocations[index - 1]
            if previousParamLoc.line! < paramLoc.line! && firstParamLoc.character! != paramLoc.character! {
                violationLocations.append(paramLoc)
            }
        }

        return violationLocations.map {
            StyleViolation(ruleDescription: type(of: self).description,
                           severity: configuration.severity,
                           location: $0)
        }
    }
}

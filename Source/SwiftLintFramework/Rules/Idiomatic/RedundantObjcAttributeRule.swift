import Foundation
import SourceKittenFramework

private let kindsImplyingObjc: Set<SwiftDeclarationAttributeKind> =
    [.ibaction, .iboutlet, .ibinspectable, .gkinspectable, .ibdesignable, .nsManaged]

public struct RedundantObjcAttributeRule: SubstitutionCorrectableRule, ConfigurationProviderRule,
    AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.warning)
    public var initializedWithNonEmptyConfiguration: Bool = false

    public init() {}

    public static let description = RuleDescription(
        identifier: "redundant_objc_attribute",
        name: "Redundant @objc Attribute",
        description: "Objective-C attribute (@objc) is redundant in declaration.",
        kind: .idiomatic,
        minSwiftVersion: .fourDotOne,
        nonTriggeringExamples: RedundantObjcAttributeRuleExamples.nonTriggeringExamples,
        triggeringExamples: RedundantObjcAttributeRuleExamples.triggeringExamples,
        corrections: RedundantObjcAttributeRuleExamples.corrections)

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        return violationRanges(in: file).map {
            StyleViolation(ruleDescription: type(of: self).description,
                           severity: configuration.severity,
                           location: Location(file: file, characterOffset: $0.location))
        }
    }

    public func violationRanges(in file: SwiftLintFile) -> [NSRange] {
        return file.structureDictionary.traverseWithParentDepthFirst { parent, subDict in
            guard let kind = subDict.declarationKind else { return nil }
            return violationRanges(file: file, kind: kind, dictionary: subDict, parentStructure: parent)
        }
    }

    private func violationRanges(file: SwiftLintFile,
                                 kind: SwiftDeclarationKind,
                                 dictionary: SourceKittenDictionary,
                                 parentStructure: SourceKittenDictionary?) -> [NSRange] {
        let objcAttribute = dictionary.swiftAttributes
                                      .first(where: { $0.attribute == SwiftDeclarationAttributeKind.objc.rawValue })
        guard let objcOffset = objcAttribute?.offset,
              let objcLength = objcAttribute?.length,
              let range = file.stringView.byteRangeToNSRange(start: objcOffset, length: objcLength),
              !dictionary.isObjcAndIBDesignableDeclaredExtension else {
            return []
        }

        let isInObjcVisibleScope = { () -> Bool in
            guard let parentStructure = parentStructure,
                let kind = dictionary.declarationKind,
                let parentKind = parentStructure.declarationKind,
                let acl = dictionary.accessibility else {
                    return false
            }

            let isInObjCExtension = [.extensionClass, .extension].contains(parentKind) &&
                parentStructure.enclosedSwiftAttributes.contains(.objc)

            let isInObjcMembers = parentStructure.enclosedSwiftAttributes.contains(.objcMembers) && !acl.isPrivate

            guard isInObjCExtension || isInObjcMembers else {
                return false
            }

            return !SwiftDeclarationKind.typeKinds.contains(kind)
        }

        let isUsedWithObjcAttribute = !Set(dictionary.enclosedSwiftAttributes).isDisjoint(with: kindsImplyingObjc)

        if isUsedWithObjcAttribute || isInObjcVisibleScope() {
            return [range]
        }

        return []
    }
}

private extension SourceKittenDictionary {
    var isObjcAndIBDesignableDeclaredExtension: Bool {
        guard let declaration = declarationKind else {
            return false
        }
        return [.extensionClass, .extension].contains(declaration)
            && Set(enclosedSwiftAttributes).isSuperset(of: [.ibdesignable, .objc])
    }
}

public extension RedundantObjcAttributeRule {
     func substitution(for violationRange: NSRange, in file: SwiftLintFile) -> (NSRange, String)? {
        var whitespaceAndNewlineOffset = 0
        let nsCharSet = CharacterSet.whitespacesAndNewlines.bridge()
        let nsContent = file.contents.bridge()
        while nsCharSet
            .characterIsMember(nsContent.character(at: violationRange.upperBound + whitespaceAndNewlineOffset)) {
                whitespaceAndNewlineOffset += 1
        }

        let withTrailingWhitespaceAndNewlineRange = NSRange(location: violationRange.location,
                                                            length: violationRange.length + whitespaceAndNewlineOffset)
        return (withTrailingWhitespaceAndNewlineRange, "")
    }
}

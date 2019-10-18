import Foundation
import SourceKittenFramework

public struct Configuration {
    // MARK: - Properties
    public static let `default` = Configuration()
    public static let fileName = ".swiftlint.yml"

    public let indentation: IndentationStyle           // style to use when indenting
    public let included: [String]                      // included
    public let excluded: [String]                      // excluded
    public let reporter: String                        // reporter (xcode, json, csv, checkstyle)
    public let warningThreshold: Int?                  // warning threshold
    public let cachePath: String?

    public var graph: Graph

    internal var computedCacheDescription: String?
    internal var configurationPath: String?            // if successfully loaded from a path

    // MARK: Rules Properties
    public var rulesStorage: RulesStorage

    /// Shortcut for rulesStorage.resultingRules
    public var rules: [Rule] { return rulesStorage.resultingRules }

    // MARK: - Initializers
    /// Initialize with all properties.
    internal init(
        rulesStorage: RulesStorage,
        included: [String],
        excluded: [String],
        warningThreshold: Int?,
        reporter: String,
        cachePath: String?,
        graph: Graph,
        indentation: IndentationStyle
    ) {
        self.rulesStorage = rulesStorage
        self.included = included
        self.excluded = excluded
        self.warningThreshold = warningThreshold
        self.reporter = reporter
        self.cachePath = cachePath
        self.graph = graph
        self.indentation = indentation
    }

    /// Initialize by copying a given configuration
    private init(copying configuration: Configuration) {
        rulesStorage = configuration.rulesStorage
        included = configuration.included
        excluded = configuration.excluded
        warningThreshold = configuration.warningThreshold
        reporter = configuration.reporter
        cachePath = configuration.cachePath
        graph = configuration.graph
        indentation = configuration.indentation
    }

    /// Initialize with all properties,
    /// except that rulesStorage is still to be synthesized from rulesMode, ruleList & allRulesWithConfigurations
    /// and a check against the pinnedVersion is performed if given.
    internal init(
        rulesMode: RulesStorage.Mode = .default(disabled: [], optIn: []),
        ruleList: RuleList = masterRuleList,
        allRulesWithConfigurations: [Rule]? = nil,
        pinnedVersion: String? = nil,
        included: [String] = [],
        excluded: [String] = [],
        warningThreshold: Int? = nil,
        reporter: String = XcodeReporter.identifier,
        cachePath: String? = nil,
        graph: Graph = Graph(rootPath: nil),
        indentation: IndentationStyle = .default
    ) {
        if let pinnedVersion = pinnedVersion, pinnedVersion != Version.current.value {
            queuedPrintError("Currently running SwiftLint \(Version.current.value) but " +
                "configuration specified version \(pinnedVersion).")
            exit(2)
        }

        let rulesStorage = RulesStorage(
            mode: rulesMode,
            allRulesWithConfigurations: allRulesWithConfigurations ?? (try? ruleList.allRules()) ?? [],
            aliasResolver: { ruleList.identifier(for: $0) ?? $0 }
        )

        self.init(
            rulesStorage: rulesStorage,
            included: included,
            excluded: excluded,
            warningThreshold: warningThreshold,
            reporter: reporter,
            cachePath: cachePath,
            graph: graph,
            indentation: indentation
        )
    }

    /// Initialize based on paths to configuration files
    public init(
        childConfigQueue: [String] = [Configuration.fileName],
        rootPath: String?, // Doesn't have a default value so that the Configuration() init isn't ambiguous
        optional: Bool = true,
        quiet: Bool = false,
        enableAllRules: Bool = false,
        cachePath: String? = nil
    ) {
        let rulesMode: RulesStorage.Mode = enableAllRules ? .allEnabled : .default(disabled: [], optIn: [])
        let cacheIdentifier = "\(childConfigQueue) - \(String(describing: rootPath))"

        if let cachedConfig = Configuration.getCached(forIdentifier: cacheIdentifier) {
            self.init(copying: cachedConfig)
        }

        let fail = { (msg: String) -> Never in
            queuedPrintError(msg)
            queuedFatalError("Could not read configuration")
        }

        do {
            var graph = try Graph(commandLineChildConfigs: childConfigQueue, rootPath: rootPath)
            let resultingConfiguration = try graph.getResultingConfiguration { dict -> Configuration in
                try Configuration(dict: dict, enableAllRules: enableAllRules, cachePath: cachePath)
            }

            self.init(copying: resultingConfiguration)
            self.graph = graph
        } catch let ConfigurationError.generic(message) {
            guard optional else { fail(message) }
            self.init(rulesMode: rulesMode, cachePath: cachePath, graph: Graph(rootPath: rootPath))
        } catch let YamlParserError.yamlParsing(message) {
            fail(message)
        } catch {
            guard optional else { fail("Unknown Error") }
            self.init(rulesMode: rulesMode, cachePath: cachePath, graph: Graph(rootPath: rootPath))
        }

        setCached(forIdentifier: cacheIdentifier)
    }
}

// MARK: - Hashable
extension Configuration: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(cachePath)
        hasher.combine(included)
        hasher.combine(excluded)
        hasher.combine(reporter)
        hasher.combine(graph)
    }

    public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        return lhs.warningThreshold == rhs.warningThreshold &&
            lhs.reporter == rhs.reporter &&
            lhs.cachePath == rhs.cachePath &&
            lhs.included == rhs.included &&
            lhs.excluded == rhs.excluded &&
            lhs.rules == rhs.rules &&
            lhs.indentation == rhs.indentation &&
            lhs.graph == rhs.graph
    }
}

// MARK: - CustomStringConvertible
extension Configuration: CustomStringConvertible {
    public var description: String {
        return "Configuration: \n"
            + "- Indentation Style: \(indentation)\n"
            + "- Included: \(included)\n"
            + "- Excluded: \(excluded)\n"
            + "- Warning Treshold: \(warningThreshold as Optional)\n"
            + "- Root Path: \(graph.rootPath as Optional)\n"
            + "- Reporter: \(reporter)\n"
            + "- Cache Path: \(cachePath as Optional)\n"
            + "- Computed Cache Description: \(computedCacheDescription as Optional)\n"
            + "- Rules: \(rules.map { type(of: $0).description.identifier })"
    }
}

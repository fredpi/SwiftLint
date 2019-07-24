import Foundation
import SourceKittenFramework

public struct Configuration: Hashable {
    // MARK: - Properties
    public static let fileName = ".swiftlint.yml"

    public let indentation: IndentationStyle           // style to use when indenting
    public let included: [String]                      // included
    public let excluded: [String]                      // excluded
    public let reporter: String                        // reporter (xcode, json, csv, checkstyle)
    public let warningThreshold: Int?                  // warning threshold
    public private(set) var rootPath: String?          // the root path to search for nested configurations
    public private(set) var configurationPath: String? // if successfully loaded from a path
    public let cachePath: String?

    internal var computedCacheDescription: String?

    // MARK: Rules Properties
    internal var rulesStorage: RulesStorage

    /// All rules enabled in this configuration, derived from disabled, opt-in and whitelist rules
    public var rules: [Rule] {
        return rulesStorage.resultingRules
    }

    // MARK: - Initializers
    public init?(
        rulesMode: RulesStorage.Mode = .default(disabled: [], optIn: []),
        included: [String] = [],
        excluded: [String] = [],
        warningThreshold: Int? = nil,
        reporter: String = XcodeReporter.identifier,
        ruleList: RuleList = masterRuleList,
        allRulesWithConfigurations: [Rule]? = nil,
        swiftlintVersion: String? = nil,
        cachePath: String? = nil,
        indentation: IndentationStyle = .default
    ) {
        if let pinnedVersion = swiftlintVersion, pinnedVersion != Version.current.value {
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
            indentation: indentation
        )
    }

    internal init(
        rulesStorage: RulesStorage,
        included: [String],
        excluded: [String],
        warningThreshold: Int?,
        reporter: String,
        cachePath: String?,
        rootPath: String? = nil,
        indentation: IndentationStyle
    ) {
        self.rulesStorage = rulesStorage
        self.included = included
        self.excluded = excluded
        self.reporter = reporter
        self.cachePath = cachePath
        self.rootPath = rootPath
        self.indentation = indentation

        // set the config threshold to the threshold provided in the config file
        self.warningThreshold = warningThreshold
    }

    private init(_ configuration: Configuration) {
        rulesStorage = configuration.rulesStorage
        included = configuration.included
        excluded = configuration.excluded
        warningThreshold = configuration.warningThreshold
        reporter = configuration.reporter
        cachePath = configuration.cachePath
        rootPath = configuration.rootPath
        indentation = configuration.indentation
    }

    public init(path: String = Configuration.fileName, rootPath: String? = nil,
                optional: Bool = true, quiet: Bool = false,
                enableAllRules: Bool = false, cachePath: String? = nil,
                subConfigPreviousPaths: [String] = []) {
        let fullPath: String
        if let rootPath = rootPath, rootPath.isDirectory() {
            fullPath = path.bridge().absolutePathRepresentation(rootDirectory: rootPath)
        } else {
            fullPath = path.bridge().absolutePathRepresentation()
        }

        if let cachedConfig = Configuration.getCached(atPath: fullPath) {
            self.init(cachedConfig)
            configurationPath = fullPath
            return
        }

        let fail = { (msg: String) in
            queuedPrintError("\(fullPath):\(msg)")
            queuedFatalError("Could not read configuration file at path '\(fullPath)'")
        }
        let rulesMode: RulesStorage.Mode = enableAllRules ? .allEnabled : .default(disabled: [], optIn: [])
        if path.isEmpty || !FileManager.default.fileExists(atPath: fullPath) {
            if !optional { fail("File not found.") }
            self.init(rulesMode: rulesMode, cachePath: cachePath)!
            self.rootPath = rootPath
            return
        }
        do {
            let yamlContents = try String(contentsOfFile: fullPath, encoding: .utf8)
            let dict = try YamlParser.parse(yamlContents)
            if !quiet {
                queuedPrintError("Loading configuration from '\(path)'")
            }
            self.init(dict: dict, enableAllRules: enableAllRules,
                      cachePath: cachePath)!

            // Merge sub config if needed
            if let subConfigFile = dict[Key.subConfig.rawValue] as? String {
                merge(
                    subConfigFile: subConfigFile, currentFilePath: fullPath, quiet: quiet,
                    subConfigPreviousPaths: subConfigPreviousPaths
                )
            }

            configurationPath = fullPath
            self.rootPath = rootPath
            setCached(atPath: fullPath)
            return
        } catch YamlParserError.yamlParsing(let message) {
            fail(message)
        } catch {
            fail("\(error)")
        }
        self.init(rulesMode: rulesMode, cachePath: cachePath)!
        setCached(atPath: fullPath)
    }

    // MARK: - Methods
    public func hash(into hasher: inout Hasher) {
        if let configurationPath = configurationPath {
            hasher.combine(configurationPath)
        } else if let rootPath = rootPath {
            hasher.combine(rootPath)
        } else if let cachePath = cachePath {
            hasher.combine(cachePath)
        } else {
            hasher.combine(included)
            hasher.combine(excluded)
            hasher.combine(reporter)
        }
    }

    private mutating func merge(
        subConfigFile: String,
        currentFilePath: String,
        quiet: Bool,
        subConfigPreviousPaths: [String]
    ) {
        let fail = { (msg: String) in
            queuedPrintError(msg)
            if let firstSubConfigFilePath = subConfigPreviousPaths.first {
                // Print entire stack of config file references
                queuedFatalError(
                    "Could not read sub config file ('\(currentFilePath)')"
                        + subConfigPreviousPaths.dropFirst().reversed().reduce("") {
                            $0 + " originating from sub config file ('\($1)')"
                        }
                        + " originating from main config file ('\(firstSubConfigFilePath)')"
                )
            } else {
                queuedFatalError(
                    "Could not read configuration file ('\(currentFilePath))')"
                )
            }
        }

        let subConfigPath = currentFilePath.bridge().deletingLastPathComponent
            .bridge().appendingPathComponent(subConfigFile)

        if subConfigFile.contains("/") {
            fail("The file specified as sub_config must be on the same level as the base config file")
        } else if !FileManager.default.fileExists(atPath: subConfigPath) {
            fail("Unable to find file specified as sub_config (\(subConfigPath))")
        } else if subConfigPreviousPaths.contains(subConfigPath) { // Avoid cyclomatic references
            let cycleDescription = (subConfigPreviousPaths + [currentFilePath, subConfigPath]).map {
                $0.bridge().lastPathComponent
            }.reduce("") { $0 + " => " + $1 }.dropFirst(4)
            fail("Invalid cycle of sub_config references: \(cycleDescription)")
        } else {
            let config = Configuration.getCached(atPath: currentFilePath) ??
                Configuration(
                    path: subConfigPath,
                    rootPath: rootPath,
                    optional: false,
                    quiet: quiet,
                    subConfigPreviousPaths: subConfigPreviousPaths + [currentFilePath]
                )

            self = merged(with: config)
        }
    }

    // MARK: Equatable
    public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        return (lhs.warningThreshold == rhs.warningThreshold) &&
            (lhs.reporter == rhs.reporter) &&
            (lhs.rootPath == rhs.rootPath) &&
            (lhs.configurationPath == rhs.configurationPath) &&
            (lhs.cachePath == rhs.cachePath) &&
            (lhs.included == rhs.included) &&
            (lhs.excluded == rhs.excluded) &&
            (lhs.rules == rhs.rules) &&
            (lhs.indentation == rhs.indentation)
    }
}

private extension String {
    func isDirectory() -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: self, isDirectory: &isDir) {
            return isDir.boolValue
        }

        return false
    }
}

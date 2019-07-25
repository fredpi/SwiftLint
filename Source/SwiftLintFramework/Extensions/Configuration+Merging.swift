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
        let pathNSString = path.bridge()
        let configurationSearchPath = pathNSString.appendingPathComponent(Configuration.fileName)
        let fullPath = pathNSString.absolutePathRepresentation()
        let cachePath = (configurationPath ?? "") + configurationSearchPath

        if let cached = Configuration.getCached(atPath: cachePath) {
            return cached
        } else {
            if path == rootDirectory || configurationSearchPath == configurationPath {
                // Use self if at level self
                return self
            } else if FileManager.default.fileExists(atPath: configurationSearchPath) {
                // Use self merged with the config that was found
                let config = merged(
                    with: Configuration(
                        path: configurationSearchPath,
                        rootPath: fullPath,
                        optional: false,
                        quiet: true
                    )
                )

                // Cache merged result to circumvent heavy merge recomputations
                config.setCached(atPath: cachePath)
                return config
            } else if path != "/" {
                // If we are not at the root path, continue down the tree
                return configuration(forPath: pathNSString.deletingLastPathComponent)
            } else {
                // Fallback to self
                return self
            }
        }
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
            rulesStorage: rulesStorage.merged(with: configuration.rulesStorage),
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

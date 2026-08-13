import Foundation

public enum DemoResourceBundle {
    public static let resourceNames = ["navigator-route", "navigator-risk-layer", "navigator-progress", "navigator-metadata"]
    public static let csvResourceNames = ["hwaseong-bike-roads"]

    public static func mainBundleContainsAllResources(bundle: Bundle = .main) -> Bool {
        resourceNames.allSatisfy { bundle.url(forResource: $0, withExtension: "json") != nil } && csvResourceNames.allSatisfy { bundle.url(forResource: $0, withExtension: "csv") != nil }
    }

    public static func containsAllResourcesIncludingPackageFallback(bundle: Bundle = .main) -> Bool {
        resourceNames.allSatisfy { name in
            bundle.url(forResource: name, withExtension: "json") != nil || Bundle.module.url(forResource: name, withExtension: "json") != nil
        } && csvResourceNames.allSatisfy { name in bundle.url(forResource: name, withExtension: "csv") != nil || Bundle.module.url(forResource: name, withExtension: "csv") != nil }
    }

    public static func data(named name: String, bundle: Bundle = .main) throws -> Data {
        if name.hasSuffix(".csv") {
            let base = String(name.dropLast(4))
            guard csvResourceNames.contains(base), let url = bundle.url(forResource: base, withExtension: "csv") ?? Bundle.module.url(forResource: base, withExtension: "csv") else { throw DemoResourceError.missing(name) }
            return try Data(contentsOf: url)
        }
        guard resourceNames.contains(name), let url = bundle.url(forResource: name, withExtension: "json") ?? Bundle.module.url(forResource: name, withExtension: "json") else { throw DemoResourceError.missing(name) }
        return try Data(contentsOf: url)
    }
}

public enum DemoResourceError: Error, Equatable, Sendable { case missing(String) }

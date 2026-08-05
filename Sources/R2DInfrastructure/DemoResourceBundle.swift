import Foundation

public enum DemoResourceBundle {
    public static let resourceNames = ["navigator-route", "navigator-risk-layer", "navigator-progress", "navigator-metadata"]

    public static func mainBundleContainsAllResources(bundle: Bundle = .main) -> Bool {
        resourceNames.allSatisfy { bundle.url(forResource: $0, withExtension: "json") != nil }
    }

    public static func containsAllResourcesIncludingPackageFallback(bundle: Bundle = .main) -> Bool {
        resourceNames.allSatisfy { name in
            bundle.url(forResource: name, withExtension: "json") != nil || Bundle.module.url(forResource: name, withExtension: "json") != nil
        }
    }

    public static func data(named name: String, bundle: Bundle = .main) throws -> Data {
        guard resourceNames.contains(name), let url = bundle.url(forResource: name, withExtension: "json") ?? Bundle.module.url(forResource: name, withExtension: "json") else { throw DemoResourceError.missing(name) }
        return try Data(contentsOf: url)
    }
}

public enum DemoResourceError: Error, Equatable, Sendable { case missing(String) }

import Foundation

public enum DemoResourceBundle {
    public static let resourceNames = ["navigator-route", "navigator-risk-layer", "navigator-progress", "navigator-metadata"]
    public static let csvResourceNames = ["hwaseong-bike-roads", "sensor-2026-08-09-route-scores", "sensor-2026-08-09-events"]

    public static func mainBundleContainsAllResources(bundle: Bundle = .main) -> Bool {
        resourceNames.allSatisfy { bundle.url(forResource: $0, withExtension: "json") != nil } && csvResourceNames.allSatisfy { bundle.url(forResource: $0, withExtension: "csv") != nil }
    }

    public static func containsAllResourcesIncludingPackageFallback(bundle: Bundle = .main) -> Bool {
        resourceNames.allSatisfy { name in
            resourceURL(named: name, extension: "json", bundle: bundle) != nil
        } && csvResourceNames.allSatisfy { name in resourceURL(named: name, extension: "csv", bundle: bundle) != nil }
    }

    public static func data(named name: String, bundle: Bundle = .main) throws -> Data {
        if name.hasSuffix(".csv") {
            let base = String(name.dropLast(4))
            guard csvResourceNames.contains(base), let url = resourceURL(named: base, extension: "csv", bundle: bundle) else { throw DemoResourceError.missing(name) }
            return try Data(contentsOf: url)
        }
        guard resourceNames.contains(name), let url = resourceURL(named: name, extension: "json", bundle: bundle) else { throw DemoResourceError.missing(name) }
        return try Data(contentsOf: url)
    }

    private static func resourceURL(named name: String, extension fileExtension: String, bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        if let nestedBundleURL = bundle.url(forResource: "R2D_R2DInfrastructure", withExtension: "bundle"),
           let nestedBundle = Bundle(url: nestedBundleURL),
           let url = nestedBundle.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        return nil
    }
}

public enum DemoResourceError: Error, Equatable, Sendable { case missing(String) }

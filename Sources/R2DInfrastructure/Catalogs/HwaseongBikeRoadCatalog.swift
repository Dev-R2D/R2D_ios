import Foundation
import R2DCore

public enum BikeRoadGeometryQuality: String, Codable, Sendable { case endpointsOnly = "ENDPOINTS_ONLY" }

public struct BikeRoadRecord: Equatable, Sendable {
    public let name: String, number: String, startAddress: String, endAddress: String, type: String, sourceDate: String
    public let start: Coordinate, end: Coordinate, publishedLengthKM: Double?, geometryQuality: BikeRoadGeometryQuality
}

public struct HwaseongBikeRoadCatalog: Sendable {
    public let roads: [BikeRoadRecord]
    public var preferredDemoRoad: BikeRoadRecord? {
        roads.first { $0.name.contains("동탄원천로 1L") } ?? roads.first
    }

    public init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw CSVError.invalidEncoding }
        // This public file has a stable 21-column schema and no embedded delimiter in the coordinate columns.
        // Positional decoding also avoids Unicode normalization differences in Korean header names.
        let rows = text.split(whereSeparator: \.isNewline).dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        roads = rows.compactMap { row in
            guard row.count >= 21, let startLat = Double(row[8]), let startLon = Double(row[9]),
                  let endLat = Double(row[10]), let endLon = Double(row[11]),
                  startLat != endLat || startLon != endLon else { return nil }
            return BikeRoadRecord(
                name: row[0], number: row[1], startAddress: row[4].isEmpty ? row[5] : row[4], endAddress: row[6].isEmpty ? row[7] : row[6],
                type: row[16], sourceDate: row[20].trimmingCharacters(in: .whitespacesAndNewlines),
                start: .init(latitude: startLat, longitude: startLon), end: .init(latitude: endLat, longitude: endLon),
                publishedLengthKM: Double(row[13]), geometryQuality: .endpointsOnly
            )
        }
        if roads.isEmpty { throw CSVError.noValidRows }
    }

    public static func loadBundled() throws -> Self {
        try .init(data: DemoResourceBundle.data(named: "hwaseong-bike-roads.csv"))
    }
}

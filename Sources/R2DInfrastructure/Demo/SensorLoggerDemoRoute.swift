import Foundation
import R2DCore

enum SensorLoggerDemoRoute {
    struct Sample {
        let coordinate: Coordinate
        let speedMps: Double
    }

    static func loadSamples() -> [Sample] {
        let routeData: Data
        do {
            routeData = try DemoResourceBundle.data(named: "sensor-2026-08-09-route-scores.csv")
        } catch {
            return []
        }

        return simpleRows(from: routeData).compactMap { row -> Sample? in
            guard
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? "")
            else { return nil }
            let speed = max(0, Double(row["speed"] ?? "") ?? 0)
            return Sample(coordinate: Coordinate(latitude: latitude, longitude: longitude), speedMps: speed)
        }
    }

    static func load() -> Route? {
        let routeData: Data
        let eventData: Data
        do {
            routeData = try DemoResourceBundle.data(named: "sensor-2026-08-09-route-scores.csv")
            eventData = try DemoResourceBundle.data(named: "sensor-2026-08-09-events.csv")
        } catch {
            return nil
        }

        let routeRows = simpleRows(from: routeData)
        let eventRows = simpleRows(from: eventData)

        let coordinates = routeRows.compactMap { row -> Coordinate? in
            guard
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? "")
            else { return nil }
            return Coordinate(latitude: latitude, longitude: longitude)
        }
        guard coordinates.count >= 2 else { return nil }

        let riskCells = eventRows.compactMap { row -> RiskCell? in
            guard
                let id = row["id"],
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? ""),
                let score = Double(row["score"] ?? "")
            else { return nil }
            let confidence = Double(row["confidence"] ?? "") ?? 1.0
            let geometry = String(format: "POINT(%.7f %.7f)", longitude, latitude)
            return RiskCell(id: "sensor-2026-08-09-event-\(id)", geometry: geometry, riskScore: score, confidence: confidence)
        }

        let distance = zip(coordinates, coordinates.dropFirst()).reduce(0) { partial, pair in
            partial + distanceMeters(pair.0, pair.1)
        }
        let first = coordinates[0]
        let last = coordinates[coordinates.count - 1]
        return Route(
            id: "sensor-2026-08-09",
            polyline: coordinates,
            totalDistance: distance,
            totalDuration: 1_480,
            providerOption: "sensor_logger",
            turnList: [
                Turn(coordinate: first, instruction: "Sensor Logger 실측 경로 출발", distance: 0),
                Turn(coordinate: last, instruction: "Sensor Logger 실측 경로 도착", distance: distance)
            ],
            riskCells: riskCells
        )
    }

    private static func distanceMeters(_ start: Coordinate, _ end: Coordinate) -> Double {
        let dy = (end.latitude - start.latitude) * 111_320
        let dx = (end.longitude - start.longitude) * 111_320 * cos(start.latitude * .pi / 180)
        return sqrt(dx * dx + dy * dy)
    }

    private static func simpleRows(from data: Data) -> [[String: String]] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text
            .replacingOccurrences(of: "\u{feff}", with: "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let headerLine = lines.first else { return [] }
        let headers = headerLine.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.dropFirst().map { line in
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                (header, index < values.count ? values[index] : "")
            })
        }
    }
}

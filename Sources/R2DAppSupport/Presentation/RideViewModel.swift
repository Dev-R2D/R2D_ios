import Combine
import Foundation
import R2DCore

public struct ReplayPresentation: Equatable, Sendable {
    public let route: Route
    public let routes: [Route]

    public init(route: Route, routes: [Route]) {
        self.route = route
        self.routes = routes
    }
}

@MainActor
public final class RideViewModel: ObservableObject {
    @Published public private(set) var state: ActiveRideState
    @Published public var summary: RideSummary?
    @Published public private(set) var sensorImportMessage: String?
    @Published public private(set) var isImportingSensorLog = false
    @Published public private(set) var originResults: [PlaceSearchResult] = []
    @Published public private(set) var destinationResults: [PlaceSearchResult] = []
    @Published public private(set) var selectedOrigin: PlaceSearchResult?
    @Published public private(set) var selectedDestination: PlaceSearchResult?
    @Published public private(set) var routeSearchMessage: String?
    @Published public private(set) var matchedPointCount = 0
    @Published public private(set) var isSearchingPlaces = false
    @Published public private(set) var isSearchingRoute = false
    @Published public private(set) var selectedRouteOption = "pm"
    @Published public private(set) var selectedDemoDistanceMeters: Double?
    @Published public private(set) var isDemoNavigating = false
    @Published public private(set) var pendingReplay: ReplayPresentation?

    public let coordinator: ActiveRideCoordinator
    public let mapRenderer: IMapRenderer
    public let featureFlags: FeatureFlags
    public let demoReplayController: DemoReplayControlling?
    public let diagnosticsSummary: String

    private let placeSearch: IPlaceSearchRepository
    private let mapMatching: IMapMatchingRepository
    private let sensorLogImporter: SensorLogImporting?
    private var unsubscribe: Unsubscribe?
    private var isAutoFinishing = false
    private var demoNavigationTask: Task<Void, Never>?
    private var recordedTrace: [Coordinate] = []
    private var lastRecordedCoordinate: Coordinate?

    public init(
        coordinator: ActiveRideCoordinator,
        mapRenderer: IMapRenderer = NoopMapRenderer(),
        featureFlags: FeatureFlags = .production,
        demoReplayController: DemoReplayControlling? = nil,
        placeSearch: IPlaceSearchRepository,
        mapMatching: IMapMatchingRepository,
        diagnosticsSummary: String = "",
        sensorLogImporter: SensorLogImporting? = nil
    ) {
        self.coordinator = coordinator
        self.mapRenderer = mapRenderer
        self.featureFlags = featureFlags
        self.demoReplayController = demoReplayController
        self.placeSearch = placeSearch
        self.mapMatching = mapMatching
        self.diagnosticsSummary = diagnosticsSummary
        self.sensorLogImporter = sensorLogImporter
        state = coordinator.getSnapshot()
        unsubscribe = coordinator.subscribe { [weak self] in self?.accept($0) }
    }

    public func bootstrap() {
        coordinator.startLocationPreview()
        Task {
            await coordinator.syncRiskViewport(
                .init(minLatitude: 37.54, minLongitude: 126.95, maxLatitude: 37.58, maxLongitude: 127.02),
                zoomLevel: 14
            )
        }
    }

    public func searchOrigin(_ query: String) {
        searchPlace(query, target: .origin)
    }

    public func searchDestination(_ query: String) {
        searchPlace(query, target: .destination)
    }

    public func selectOrigin(at index: Int) {
        guard originResults.indices.contains(index) else { return }
        selectedOrigin = originResults[index]
        alignCurrentLocationToOrigin(originResults[index].coordinate)
        routeSearchMessage = "출발지 선택: \(originResults[index].title)"
    }

    public func selectDestination(at index: Int) {
        guard destinationResults.indices.contains(index) else { return }
        selectedDestination = destinationResults[index]
        routeSearchMessage = "도착지 선택: \(destinationResults[index].title)"
    }

    public func searchRouteWithSelectedPlaces() {
        runRouteSearch()
    }

    public func searchRoute(originQuery: String, destinationQuery: String) {
        let originQuery = originQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationQuery = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originQuery.isEmpty, !destinationQuery.isEmpty else {
            routeSearchMessage = "출발지와 도착지를 입력해 주세요."
            return
        }
        isSearchingRoute = true
        routeSearchMessage = "주소 확인 후 iMPS 경로 탐색 중..."
        Task {
            do {
                let originResults: [PlaceSearchResult]
                let origin: PlaceSearchResult?
                if isCurrentLocationQuery(originQuery) {
                    guard let currentOrigin = await currentLocationOrigin() else {
                        isSearchingRoute = false
                        return
                    }
                    originResults = [currentOrigin]
                    origin = currentOrigin
                } else {
                    originResults = try await placeSearch.geocode(originQuery, near: state.location.coordinate)
                    origin = originResults.first
                }

                let destinationResults = try await placeSearch.geocode(destinationQuery, near: origin?.coordinate ?? state.location.coordinate)
                let destination = destinationResults.first

                guard let origin, let destination else {
                    routeSearchMessage = "주소 검색 결과가 없습니다."
                    isSearchingRoute = false
                    return
                }
                selectedOrigin = origin
                selectedDestination = destination
                self.originResults = originResults
                self.destinationResults = destinationResults
                alignCurrentLocationToOrigin(origin.coordinate)
                runRouteSearch()
            } catch {
                routeSearchMessage = "주소 확인 실패: \(error.localizedDescription)"
                isSearchingRoute = false
            }
        }
    }

    private func runRouteSearch() {
        guard let origin = selectedOrigin, let destination = selectedDestination else {
            routeSearchMessage = "출발지와 도착지를 먼저 검색해서 선택해 주세요."
            return
        }
        alignCurrentLocationToOrigin(origin.coordinate)
        guard Self.isSupportedIMPSKoreaCoordinate(origin.coordinate), Self.isSupportedIMPSKoreaCoordinate(destination.coordinate) else {
            routeSearchMessage = """
            iMPS 경로 탐색은 한국 좌표에서만 가능합니다.
            현재 출발 좌표: \(Self.coordinateText(origin.coordinate))
            Simulator > Features > Location > Custom Location에서 한국 좌표로 바꿔 주세요.
            """
            return
        }
        isSearchingRoute = true
        routeSearchMessage = "iMPS PM 후보 경로 3개 탐색 중..."
        Task {
            do {
                try await coordinator.searchRouteOptions(origin: origin.coordinate, destination: destination.coordinate, options: Self.comparisonRouteOptions)
                let snapshot = coordinator.getSnapshot()
                if let selected = snapshot.routes.first(where: { $0.providerOption == selectedRouteOption }) ?? snapshot.routes.first {
                    coordinator.selectRoute(selected)
                    let count = coordinator.getSnapshot().routes.count
                    if let duplicateMessage = duplicateRouteMessage(for: snapshot.routes) {
                        routeSearchMessage = "PM 후보 경로 \(count)개 표시: \(summaryText(for: selected))\n\(duplicateMessage)"
                    } else {
                        routeSearchMessage = "PM 후보 경로 \(count)개 표시: \(summaryText(for: selected))"
                    }
                } else {
                    routeSearchMessage = "경로 결과가 없습니다."
                }
            } catch {
                routeSearchMessage = Self.routeSearchErrorMessage(error, origin: origin.coordinate, destination: destination.coordinate)
            }
            isSearchingRoute = false
        }
    }

    public func mapMatchSelectedRoute() {
        guard let route = state.selectedRoute ?? state.routes.first else {
            routeSearchMessage = "맵매칭할 경로가 없습니다."
            return
        }
        routeSearchMessage = "Special Map Matching 요청 중..."
        Task {
            do {
                let matched = try await mapMatching.matchTrace(route.polyline)
                matchedPointCount = matched.count
                routeSearchMessage = "맵매칭 완료: \(matched.count)개 지점 복원"
            } catch {
                routeSearchMessage = "맵매칭 실패: \(error.localizedDescription)"
            }
        }
    }

    public func startSelectedRoute() {
        if state.selectedRoute == nil, let first = state.routes.first {
            coordinator.selectRoute(first)
        }
        guard state.selectedRoute != nil else {
            routeSearchMessage = "먼저 경로 탐색을 완료해 주세요."
            return
        }
        do {
            if state.session == nil {
                _ = try coordinator.prepare()
            }
            beginTraceRecording()
            do {
                _ = try coordinator.start()
                coordinator.switchView(.navigator)
                isDemoNavigating = true
                routeSearchMessage = "주행 시작: 실시간 위치/센서 연동"
                sensorImportMessage = "센서로거 IMU & GPS 실시간 연동 주행 시작 · \(demoDistanceLabel)"
                startDemoNavigationIfNeeded()
            } catch {
                coordinator.switchView(.navigator)
                isDemoNavigating = true
                routeSearchMessage = "데모 주행 시작: 실제 위치/센서 수집 없이 내비 화면을 표시합니다."
                sensorImportMessage = "데모 주행 시작: \(demoDistanceLabel) · \(error.localizedDescription)"
                startDemoNavigationIfNeeded(force: true)
            }
        } catch {
            routeSearchMessage = "주행 시작 실패: \(error.localizedDescription)"
            sensorImportMessage = "주행 시작 실패: \(error.localizedDescription)"
            endTraceRecording()
        }
    }

    public func finishRide() {
        if isDemoNavigating, state.session?.state != .active, state.session?.state != .paused {
            stopDemoNavigation()
            isDemoNavigating = false
            routeSearchMessage = "데모 주행 종료: 준비 화면으로 돌아왔습니다."
            presentReplayIfPossible()
            return
        }
        Task {
            stopDemoNavigation()
            summary = try? await coordinator.finish()
            isDemoNavigating = false
            isAutoFinishing = false
            presentReplayIfPossible()
        }
    }

    public func returnToHome() {
        summary = nil
        bootstrap()
    }

    public func importSensorLogs(_ urls: [URL]) {
        guard let sensorLogImporter else {
            sensorImportMessage = "Sensor Logger 가져오기를 사용할 수 없습니다."
            return
        }
        isImportingSensorLog = true
        sensorImportMessage = "Sensor Logger 파일 읽기 및 GPS/IMU 추출 중..."
        Task {
            do {
                let result = try await sensorLogImporter.importRecording(from: urls)
                if let first = result.extractedCoordinates.first, let last = result.extractedCoordinates.last {
                    let route = Route(
                        id: "sensorlogger-route-\(UUID().uuidString.prefix(4))",
                        polyline: result.extractedCoordinates,
                        totalDistance: 3200,
                        totalDuration: 540,
                        turnList: [
                            Turn(coordinate: first, instruction: "Sensor Logger 수집 출발 지점", distance: 0),
                            Turn(coordinate: last, instruction: "Sensor Logger 수집 도착 지점", distance: 3200)
                        ],
                        riskCells: []
                    )
                    coordinator.selectRoute(route)
                    coordinator.injectExternalLocation(LocationSnapshot(coordinate: first, speedMps: 4.5, heading: 90, mapMatchConfidence: 0.95))
                }
                sensorImportMessage = "Sensor Logger 연동 완료 (GPS \(result.extractedCoordinates.count)개 / IMU 충격 \(result.imuSpikeCount)개)"
            } catch {
                sensorImportMessage = "가져오기 실패: \(error.localizedDescription)"
            }
            isImportingSensorLog = false
        }
    }

    public func sensorImportPickerFailed(_ error: Error) {
        sensorImportMessage = "파일 선택 실패: \(error.localizedDescription)"
    }

    private func accept(_ value: ActiveRideState) {
        state = value
        recordTraceCoordinateIfNeeded(value.location.coordinate)
        guard featureFlags.replayLocationEnabled,
              !isAutoFinishing,
              value.session?.state == .active,
              value.navigationProgress?.progressRatio ?? 0 >= 0.995
        else { return }
        isAutoFinishing = true
        finishRide()
    }

    private enum PlaceTarget {
        case origin
        case destination
    }

    public static func bicycleDurationText(distanceMeters: Double, averageSpeedKPH: Double = 15) -> String {
        let minutes = max(1, Int((distanceMeters / 1_000 / averageSpeedKPH * 60).rounded()))
        if minutes < 60 { return "\(minutes)분" }
        return "\(minutes / 60)시간 \(minutes % 60)분"
    }

    public static let comparisonRouteOptions = [
        "pm",
        "pm_main_road",
        "pm_short_distance_priority"
    ]

    public static func routeDurationLabel(for route: Route) -> String {
        if isPMRoute(route.providerOption) {
            return "PM 예상 \(durationText(seconds: route.totalDuration))"
        }
        return "자전거 환산 \(bicycleDurationText(distanceMeters: route.totalDistance))"
    }

    public static func durationText(seconds: TimeInterval) -> String {
        let totalSeconds = max(1, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)분" : "\(minutes)분 \(seconds)초"
        }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return remainMinutes == 0 ? "\(hours)시간" : "\(hours)시간 \(remainMinutes)분"
    }

    public static func isPMRoute(_ option: String?) -> Bool {
        option?.hasPrefix("pm") == true
    }

    public static func isSupportedIMPSKoreaCoordinate(_ coordinate: Coordinate) -> Bool {
        (33.0...39.5).contains(coordinate.latitude) && (124.0...132.5).contains(coordinate.longitude)
    }

    public static func coordinateText(_ coordinate: Coordinate) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    public static func routeSearchErrorMessage(_ error: Error, origin: Coordinate, destination: Coordinate) -> String {
        if error as? RouteRepositoryError == .invalidRoute {
            return """
            경로 탐색 실패: iMPS가 경로를 만들 수 없습니다.
            출발 \(coordinateText(origin)) → 도착 \(coordinateText(destination))
            현재 위치가 한국 밖이면 Simulator 위치를 한국 좌표로 바꿔 주세요.
            """
        }
        return "경로 탐색 실패: \(error.localizedDescription)"
    }

    public func selectRouteOption(_ option: String) {
        selectedRouteOption = option
        if let route = state.routes.first(where: { $0.providerOption == option }) {
            coordinator.selectRoute(route)
        }
        routeSearchMessage = "경로 옵션 선택: \(Self.routeOptionDisplayName(option))"
    }

    public func selectDemoDistance(_ distanceMeters: Double?) {
        selectedDemoDistanceMeters = distanceMeters
        routeSearchMessage = "데모 주행거리 선택: \(demoDistanceLabel)"
    }

    public var demoDistanceLabel: String {
        guard let selectedDemoDistanceMeters else { return "전체 경로" }
        return Self.demoDistanceLabel(for: selectedDemoDistanceMeters)
    }

    public func displayedDistance(for route: Route) -> Double {
        min(selectedDemoDistanceMeters ?? route.totalDistance, route.totalDistance)
    }

    public func displayedDuration(for route: Route) -> TimeInterval {
        let distance = displayedDistance(for: route)
        if Self.isPMRoute(route.providerOption) {
            let ratio = route.totalDistance > 0 ? distance / route.totalDistance : 1
            return max(1, route.totalDuration * ratio)
        }
        let minutes = max(1, distance / 1_000 / 15 * 60)
        return minutes * 60
    }

    public func selectRoute(id: String) {
        guard let route = state.routes.first(where: { $0.id == id }) else { return }
        coordinator.selectRoute(route)
        routeSearchMessage = "선택 경로 변경: \(summaryText(for: route))"
    }

    public func consumePendingReplay() {
        pendingReplay = nil
    }

    private func alignCurrentLocationToOrigin(_ coordinate: Coordinate) {
        coordinator.injectExternalLocation(
            LocationSnapshot(coordinate: coordinate, speedMps: 0, heading: 0, mapMatchConfidence: 1)
        )
    }

    private func beginTraceRecording() {
        recordedTrace = []
        lastRecordedCoordinate = nil
        if let coordinate = state.location.coordinate {
            recordTraceCoordinateIfNeeded(coordinate)
        } else if let origin = selectedOrigin?.coordinate {
            recordTraceCoordinateIfNeeded(origin)
        }
    }

    private func endTraceRecording() {
        stopDemoNavigation()
    }

    private func stopDemoNavigation() {
        demoNavigationTask?.cancel()
        demoNavigationTask = nil
    }

    private func startDemoNavigationIfNeeded(force: Bool = false) {
        stopDemoNavigation()
        guard force || state.session?.state != .active else { return }
        guard let route = state.selectedRoute ?? state.routes.first else { return }
        let traveledDistance = displayedDistance(for: route)
        let traceCoordinates = clippedCoordinates(for: route, maxDistance: traveledDistance)
        guard traceCoordinates.count > 1 else { return }

        demoNavigationTask = Task { [weak self] in
            guard let self else { return }
            for index in traceCoordinates.indices {
                if Task.isCancelled { return }
                let current = traceCoordinates[index]
                let next = traceCoordinates[min(index + 1, traceCoordinates.count - 1)]
                let heading = Self.heading(from: current, to: next)
                await MainActor.run {
                    self.coordinator.injectExternalLocation(
                        LocationSnapshot(
                            coordinate: current,
                            speedMps: 16.0,
                            heading: heading,
                            mapMatchConfidence: 0.98
                        )
                    )
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func recordTraceCoordinateIfNeeded(_ coordinate: Coordinate?) {
        guard isDemoNavigating || state.session?.state == .active else { return }
        guard let coordinate else { return }
        if let lastRecordedCoordinate, Self.distance(from: lastRecordedCoordinate, to: coordinate) < 3 {
            return
        }
        recordedTrace.append(coordinate)
        lastRecordedCoordinate = coordinate
    }

    private func presentReplayIfPossible() {
        defer { endTraceRecording() }
        guard let baseRoute = state.selectedRoute ?? state.routes.first else { return }
        let replayCoordinates = recordedTrace.count >= 2 ? recordedTrace : clippedCoordinates(for: baseRoute, maxDistance: displayedDistance(for: baseRoute))
        guard replayCoordinates.count >= 2 else { return }

        let replayRoute = Route(
            id: "\(baseRoute.id)-replay",
            polyline: replayCoordinates,
            totalDistance: replayDistance(for: replayCoordinates),
            totalDuration: displayedDuration(for: baseRoute),
            providerOption: baseRoute.providerOption,
            tollFee: baseRoute.tollFee,
            taxiFare: baseRoute.taxiFare,
            totalTaxiFare: baseRoute.totalTaxiFare,
            isHighWay: baseRoute.isHighWay,
            turnList: baseRoute.turnList,
            riskCells: baseRoute.riskCells
        )
        pendingReplay = ReplayPresentation(route: replayRoute, routes: [replayRoute])
    }

    private func clippedCoordinates(for route: Route, maxDistance: Double) -> [Coordinate] {
        guard let first = route.polyline.first else { return [] }
        guard maxDistance > 0 else { return [first] }
        var output: [Coordinate] = [first]
        var accumulated = 0.0

        for (start, end) in zip(route.polyline, route.polyline.dropFirst()) {
            let segmentDistance = Self.distance(from: start, to: end)
            if accumulated + segmentDistance <= maxDistance {
                output.append(end)
                accumulated += segmentDistance
                continue
            }

            let remain = maxDistance - accumulated
            let ratio = max(0, min(1, segmentDistance == 0 ? 0 : remain / segmentDistance))
            let interpolated = Coordinate(
                latitude: start.latitude + (end.latitude - start.latitude) * ratio,
                longitude: start.longitude + (end.longitude - start.longitude) * ratio
            )
            output.append(interpolated)
            break
        }

        return output
    }

    private func replayDistance(for coordinates: [Coordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { partial, pair in
            partial + Self.distance(from: pair.0, to: pair.1)
        }
    }

    private static func distance(from start: Coordinate, to end: Coordinate) -> Double {
        let dy = (end.latitude - start.latitude) * 111_320
        let dx = (end.longitude - start.longitude) * 111_320 * cos(start.latitude * .pi / 180)
        return sqrt(dx * dx + dy * dy)
    }

    private static func heading(from start: Coordinate, to end: Coordinate) -> Double {
        let delta = (end.longitude - start.longitude) * .pi / 180
        let latitudeA = start.latitude * .pi / 180
        let latitudeB = end.latitude * .pi / 180
        let y = sin(delta) * cos(latitudeB)
        let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func routeOptionDisplayName(_ option: String) -> String {
        switch option {
        case "all": return "전체 옵션"
        case "recommendation": return "추천 경로"
        case "time_priority": return "최소 시간"
        case "short_distance_priority": return "차량 최단 거리"
        case "real_traffic_freeroad": return "차량 무료 도로"
        case "motorcycle": return "이륜차"
        case "pm", "pm_recommendation": return "PM 추천 경로"
        case "pm_short_distance_priority": return "PM 최단 거리"
        case "pm_easy_way": return "PM 편한 경로"
        case "pm_time_priority": return "PM 최소 시간"
        case "pm_main_road": return "PM 큰길 위주"
        default: return option
        }
    }

    public static func demoDistanceLabel(for distanceMeters: Double) -> String {
        if distanceMeters >= 1000 {
            return String(format: "%.0fkm 데모", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters))m 데모"
    }

    private func summaryText(for route: Route) -> String {
        "\(Self.routeOptionDisplayName(route.providerOption ?? selectedRouteOption)) · \(Int(route.totalDistance))m · \(Self.routeDurationLabel(for: route))"
    }

    private func duplicateRouteMessage(for routes: [Route]) -> String? {
        guard routes.count >= 2 else { return nil }

        var grouped: [String: [Route]] = [:]
        for route in routes {
            grouped[routeFingerprint(route), default: []].append(route)
        }

        let duplicatedGroups = grouped.values.filter { $0.count > 1 }
        guard !duplicatedGroups.isEmpty else { return nil }

        let descriptions = duplicatedGroups.map { group in
            group
                .map { Self.routeOptionDisplayName($0.providerOption ?? selectedRouteOption) }
                .joined(separator: ", ")
        }
        .joined(separator: " / ")

        return "참고: \(descriptions) 결과가 같은 경로로 반환되었습니다."
    }

    private func routeFingerprint(_ route: Route) -> String {
        let sample = sampledCoordinates(from: route.polyline, maxCount: 12)
        let points = sample.map { point in
            "\(rounded(point.latitude)):\(rounded(point.longitude))"
        }
        return "\(Int(route.totalDistance.rounded()))|" + points.joined(separator: "|")
    }

    private func sampledCoordinates(from coordinates: [Coordinate], maxCount: Int) -> [Coordinate] {
        guard coordinates.count > maxCount, maxCount > 1 else { return coordinates }
        let step = Double(coordinates.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            coordinates[Int((Double(index) * step).rounded())]
        }
    }

    private func rounded(_ value: Double) -> String {
        String(format: "%.5f", value)
    }

    private func searchPlace(_ query: String, target: PlaceTarget) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            routeSearchMessage = "검색어를 입력해 주세요."
            return
        }
        if target == .origin, isCurrentLocationQuery(trimmed) {
            Task {
                guard let currentOrigin = await currentLocationOrigin() else { return }
                originResults = [currentOrigin]
                selectedOrigin = currentOrigin
                routeSearchMessage = "출발지 선택: \(currentOrigin.title)"
            }
            return
        }
        isSearchingPlaces = true
        routeSearchMessage = "주소 검색 중..."
        Task {
            do {
                let results = try await placeSearch.geocode(trimmed, near: state.location.coordinate)
                switch target {
                case .origin:
                    originResults = results
                    selectedOrigin = results.first
                case .destination:
                    destinationResults = results
                    selectedDestination = results.first
                }
                routeSearchMessage = results.first.map { "검색 완료: \($0.title) [\($0.source)]" } ?? "검색 결과가 없습니다."
            } catch {
                routeSearchMessage = "주소 검색 실패: \(error.localizedDescription)"
            }
            isSearchingPlaces = false
        }
    }

    private func isCurrentLocationQuery(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "현재 위치" || normalized == "현재위치" || normalized == "내 위치" || normalized == "내위치" || normalized == "current location"
    }

    private func currentLocationOrigin() async -> PlaceSearchResult? {
        guard let coordinate = state.location.coordinate else {
            routeSearchMessage = "내 현재 위치를 아직 받지 못했습니다. 위치 권한을 허용하고 Simulator > Features > Location에서 위치를 지정해 주세요."
            return nil
        }

        do {
            if let reversed = try await placeSearch.reverseGeocode(coordinate) {
                return .init(
                    id: "current-location",
                    title: "내 현재 위치",
                    address: reversed.address.isEmpty ? reversed.title : reversed.address,
                    coordinate: coordinate,
                    source: reversed.source
                )
            }
        } catch {
            routeSearchMessage = "현재 좌표는 받았지만 주소 변환 실패: \(error.localizedDescription)"
        }

        return .init(
            id: "current-location",
            title: "내 현재 위치",
            address: String(format: "GPS %.5f, %.5f", coordinate.latitude, coordinate.longitude),
            coordinate: coordinate,
            source: "core-location"
        )
    }
}

#if canImport(UIKit)
import UIKit
import CoreLocation
import R2DCore
import R2DInfrastructure

#if canImport(GoogleMaps)
import GoogleMaps
#endif
#if canImport(iNaviMaps)
import iNaviMaps
#endif

public final class R2DMapViewController: UIViewController {
    private struct SensorScorePoint {
        let time: TimeInterval
        let coordinate: Coordinate
        let score: Double
        let confidence: Double
        let eligible: Bool
    }

    private struct SensorRiskSpot {
        let id: String
        let coordinate: Coordinate
        let score: Double
        let time: TimeInterval
        let decision: String
        let isVideoSupported: Bool
    }

    private static let defaultCenter = Coordinate(latitude: 37.566535, longitude: 126.977969)
    private let route: Route?
    private let routes: [Route]
    private let riskRoutes: [Route]
    private let matchedTrace: [MatchedRoadPoint]
    private let initialCurrentLocation: Coordinate?
    private let followsUserLocation: Bool
    private let onRouteSelected: ((Route) -> Void)?
    private let onOffRouteDemo: (() -> Void)?
    private let rideStateProvider: ActiveRideCoordinator?
    private let locationManager = CLLocationManager()
    private var didCenterOnUserLocation = false
    private var selectedRouteID: String?
    private var rideStateUnsubscribe: Unsubscribe?
    private let zoomControl = UIStackView()
    private let coordinatePanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let coordinateLabel = UILabel()
    private var elevationTask: Task<Void, Never>?
    #if canImport(GoogleMaps)
    private weak var googleMapView: GMSMapView?
    private var googleRoutePolylineMap: [String: GMSPolyline] = [:]
    private var googleRoutePolylines: [GMSPolyline] = []
    private var googleScoreSegmentPolylines: [GMSPolyline] = []
    private var googleRouteIndexMap: [String: Int] = [:]
    private var googleRouteStartMarker: GMSMarker?
    private var googleRouteEndMarker: GMSMarker?
    private var googleUserLocationMarker: GMSMarker?
    private var googleRiskMarkers: [GMSMarker] = []
    private var googleRiskCircles: [GMSCircle] = []
    private var googleInspectMarker: GMSMarker?
    private var googleOriginalTracePolyline: GMSPolyline?
    private var googleMatchedTracePolyline: GMSPolyline?
    private var googleMapMatchDebugMarkers: [GMSMarker] = []
    #endif
    #if canImport(iNaviMaps)
    private weak var mapView: InaviMapView?
    private var routePolylines: [INVPolyline] = []
    private var scoreSegmentPolylines: [INVPolyline] = []
    private var routePolylineMap: [String: INVPolyline] = [:]
    private var routePolylineIndexMap: [String: Int] = [:]
    private var routeStartMarker: INVMarker?
    private var routeEndMarker: INVMarker?
    private var userLocationMarker: INVMarker?
    private var riskMarkers: [INVMarker] = []
    private var originalTracePolyline: INVPolyline?
    private var matchedTracePolyline: INVPolyline?
    private var mapMatchDebugMarkers: [INVMarker] = []
    private let infoWindowDataSource = R2DInfoWindowDataSource()
    private var routeStartInfoWindow: INVInfoWindow?
    private var clusterManager: INVClusterManager?
    private var clusterItems: [R2DClusterItem] = []
    #endif

    public init(
        route: Route? = nil,
        routes: [Route] = [],
        riskRoutes: [Route]? = nil,
        matchedTrace: [MatchedRoadPoint] = [],
        initialCurrentLocation: Coordinate? = nil,
        followsUserLocation: Bool = true,
        rideStateProvider: ActiveRideCoordinator? = nil,
        onOffRouteDemo: (() -> Void)? = nil,
        onRouteSelected: ((Route) -> Void)? = nil
    ) {
        self.route = route
        self.routes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        self.riskRoutes = riskRoutes ?? self.routes
        self.matchedTrace = matchedTrace
        self.initialCurrentLocation = initialCurrentLocation
        self.followsUserLocation = followsUserLocation
        self.rideStateProvider = rideStateProvider
        self.onOffRouteDemo = onOffRouteDemo
        self.onRouteSelected = onRouteSelected
        selectedRouteID = route?.id ?? routes.first?.id
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.13, blue: 0.15, alpha: 1)
        title = "R2D 지도"
        installMapView()
        installOffRouteDemoButtonIfNeeded()
        bindRideStateIfNeeded()
        startUserLocationUpdates()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        locationManager.stopUpdatingLocation()
    }

    deinit {
        rideStateUnsubscribe?()
        elevationTask?.cancel()
    }

    private func installMapView() {
        #if canImport(GoogleMaps)
        let center = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let camera = GMSCameraPosition.camera(withLatitude: center.latitude, longitude: center.longitude, zoom: 14)
        let mapView = GMSMapView(frame: view.bounds, camera: camera)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.settings.myLocationButton = true
        view.addSubview(mapView)
        googleMapView = mapView

        addGoogleRoutePolyline(on: mapView)
        addGoogleScoreSegments(on: mapView)
        addGoogleRouteMarkers(on: mapView)
        addGoogleRiskMarkers(on: mapView)
        fitGoogleCameraToRoute(on: mapView)
        installZoomControl()
        installCoordinatePanel()
        #elseif canImport(iNaviMaps)
        let options = INVMapOptions()
        options.mapType = .normal
        let initialCenter = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        options.camera = INVCameraPosition(
            INVLatLng(lat: initialCenter.latitude, lng: initialCenter.longitude),
            zoom: 14
        )

        let mapView = InaviMapView(frame: view.bounds, options: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        self.mapView = mapView

        configureMapView(mapView)
        logCoordinateConversionSample()
        addRoutePolyline(on: mapView)
        addScoreSegments(on: mapView)
        addRouteMarkers(on: mapView)
        addRiskMarkers(on: mapView)
        fitCameraToRoute(on: mapView)
        configureInfoWindow(on: mapView)
        configureClusterManager(on: mapView)
        installZoomControl()
        installCoordinatePanel()
        #else
        let label = UILabel()
        label.text = "iNavi 지도 모듈을 연결하면 여기에 지도가 표시됩니다."
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        #endif
    }

    private func selectRoute(_ route: Route) {
        selectedRouteID = route.id
        #if canImport(GoogleMaps)
        refreshGoogleRoutePolylineStyles()
        #endif
        #if canImport(iNaviMaps)
        refreshRoutePolylineStyles()
        #endif
        onRouteSelected?(route)
    }

    private func installZoomControl() {
        zoomControl.axis = .vertical
        zoomControl.spacing = 8
        zoomControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomControl)

        let plus = zoomButton(title: "+", action: #selector(zoomIn))
        let minus = zoomButton(title: "-", action: #selector(zoomOut))
        zoomControl.addArrangedSubview(plus)
        zoomControl.addArrangedSubview(minus)

        NSLayoutConstraint.activate([
            zoomControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            zoomControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func zoomButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 26, weight: .bold)
        button.backgroundColor = .white
        button.tintColor = .black
        button.layer.cornerRadius = 8
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 5
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.widthAnchor.constraint(equalToConstant: 46).isActive = true
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func installOffRouteDemoButtonIfNeeded() {
        guard onOffRouteDemo != nil else { return }
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "경로 이탈 데모"
        config.baseBackgroundColor = .systemOrange
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(runOffRouteDemo), for: .touchUpInside)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func runOffRouteDemo() {
        onOffRouteDemo?()
    }

    private func installCoordinatePanel() {
        coordinatePanel.translatesAutoresizingMaskIntoConstraints = false
        coordinatePanel.layer.cornerRadius = 14
        coordinatePanel.clipsToBounds = true
        coordinatePanel.isHidden = true
        view.addSubview(coordinatePanel)

        coordinateLabel.translatesAutoresizingMaskIntoConstraints = false
        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        coordinateLabel.textColor = .white
        coordinateLabel.numberOfLines = 2
        coordinatePanel.contentView.addSubview(coordinateLabel)

        NSLayoutConstraint.activate([
            coordinatePanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            coordinatePanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            coordinatePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            coordinateLabel.leadingAnchor.constraint(equalTo: coordinatePanel.contentView.leadingAnchor, constant: 14),
            coordinateLabel.trailingAnchor.constraint(equalTo: coordinatePanel.contentView.trailingAnchor, constant: -14),
            coordinateLabel.topAnchor.constraint(equalTo: coordinatePanel.contentView.topAnchor, constant: 11),
            coordinateLabel.bottomAnchor.constraint(equalTo: coordinatePanel.contentView.bottomAnchor, constant: -11)
        ])
    }

    private func inspectCoordinate(_ coordinate: Coordinate) {
        coordinatePanel.isHidden = false
        coordinateLabel.text = coordinateInfoText(coordinate, elevationText: "고도 확인 중...")

        #if canImport(GoogleMaps)
        if let googleMapView {
            let position = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let marker = googleInspectMarker {
                marker.position = position
            } else {
                let marker = GMSMarker(position: position)
                marker.title = "선택 위치"
                marker.icon = GMSMarker.markerImage(with: .systemIndigo)
                marker.zIndex = 260
                marker.map = googleMapView
                googleInspectMarker = marker
            }
        }
        #endif

        elevationTask?.cancel()
        elevationTask = Task { [weak self] in
            guard let self else { return }
            let elevationText: String
            do {
                let elevation = try await Self.fetchElevation(for: coordinate)
                elevationText = String(format: "고도 %.1fm", elevation)
            } catch {
                elevationText = "고도 확인 실패"
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.coordinateLabel.text = self.coordinateInfoText(coordinate, elevationText: elevationText)
            }
        }
    }

    private func coordinateInfoText(_ coordinate: Coordinate, elevationText: String) -> String {
        String(format: "경로 위치  위도 %.7f  경도 %.7f\n%@", coordinate.latitude, coordinate.longitude, elevationText)
    }

    private func inspectRouteIfNeeded(at coordinate: Coordinate) {
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        guard let routeCoordinate = nearestRouteCoordinate(to: coordinate, in: visibleRoutes, maximumDistanceMeters: 25) else {
            coordinatePanel.isHidden = true
            elevationTask?.cancel()
            #if canImport(GoogleMaps)
            googleInspectMarker?.map = nil
            googleInspectMarker = nil
            #endif
            return
        }
        inspectCoordinate(routeCoordinate)
    }

    private func nearestRouteCoordinate(to coordinate: Coordinate, in routes: [Route], maximumDistanceMeters: Double) -> Coordinate? {
        var best: (coordinate: Coordinate, distance: Double)?
        for route in routes {
            for segment in zip(route.polyline, route.polyline.dropFirst()) {
                let projected = projectedCoordinate(coordinate, ontoSegmentFrom: segment.0, to: segment.1)
                let distance = visualDistance(coordinate, projected)
                if best == nil || distance < best!.distance {
                    best = (projected, distance)
                }
            }
        }
        guard let best, best.distance <= maximumDistanceMeters else { return nil }
        return best.coordinate
    }

    private func projectedCoordinate(_ coordinate: Coordinate, ontoSegmentFrom start: Coordinate, to end: Coordinate) -> Coordinate {
        let metersPerLongitude = max(1, 111_320 * cos(start.latitude * .pi / 180))
        let ax = start.longitude * metersPerLongitude
        let ay = start.latitude * 111_320
        let bx = end.longitude * metersPerLongitude
        let by = end.latitude * 111_320
        let px = coordinate.longitude * metersPerLongitude
        let py = coordinate.latitude * 111_320
        let dx = bx - ax
        let dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }
        let ratio = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
        return Coordinate(
            latitude: (ay + ratio * dy) / 111_320,
            longitude: (ax + ratio * dx) / metersPerLongitude
        )
    }

    private static func fetchElevation(for coordinate: Coordinate) async throws -> Double {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "R2DGoogleMapsAPIKey") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElevationError.missingAPIKey
        }
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/elevation/json")
        components?.queryItems = [
            URLQueryItem(name: "locations", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = components?.url else { throw ElevationError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ElevationError.invalidResponse }
        let decoded = try JSONDecoder().decode(ElevationResponse.self, from: data)
        guard decoded.status == "OK", let elevation = decoded.results.first?.elevation else {
            throw ElevationError.invalidResponse
        }
        return elevation
    }

    private static func loadBundledSensorRiskCells() -> [RiskCell] {
        loadBundledSensorRiskSpots().map { spot in
            RiskCell(
                id: spot.id,
                geometry: String(format: "POINT(%.7f %.7f)", spot.coordinate.latitude, spot.coordinate.longitude),
                riskScore: spot.score,
                confidence: spot.isVideoSupported ? 0.9 : 0.7
            )
        }
    }

    private static func loadBundledSensorRiskSpots() -> [SensorRiskSpot] {
        guard let data = try? DemoResourceBundle.data(named: "sensor-2026-08-09-events.csv"),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return simpleCSVRows(text).compactMap { row -> SensorRiskSpot? in
            guard
                let id = row["id"],
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? "")
            else { return nil }
            let score = Double(row["score"] ?? "") ?? 40
            let visualStatus = (row["visualStatus"] ?? "").lowercased()
            let decision = row["decision"]?.isEmpty == false ? row["decision"]! : "충격 이벤트 후보"
            return SensorRiskSpot(
                id: "bundled-sensor-risk-\(id)",
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                score: score,
                time: Double(row["time"] ?? "") ?? 0,
                decision: decision,
                isVideoSupported: visualStatus == "video-linked" || visualStatus == "supported"
            )
        }
    }

    private static func loadBundledSensorScorePoints() -> [SensorScorePoint] {
        guard let data = try? DemoResourceBundle.data(named: "sensor-2026-08-09-route-scores.csv"),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return simpleCSVRows(text).compactMap { row -> SensorScorePoint? in
            guard
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? "")
            else { return nil }
            let score = Double(row["score"] ?? "") ?? 0
            let accuracy = Double(row["horizontalAccuracy"] ?? "") ?? 30
            let speed = Double(row["speed"] ?? "") ?? 0
            let eligibleText = (row["eligible"] ?? "").lowercased()
            let eligible = eligibleText == "true" || eligibleText == "1"
            let confidence = eligible ? max(0.45, min(0.94, 0.98 - accuracy / 100)) : 0.35
            return SensorScorePoint(
                time: Double(row["seconds_elapsed"] ?? "") ?? 0,
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                score: score,
                confidence: speed < 1.5 ? min(confidence, 0.46) : confidence,
                eligible: eligible
            )
        }
    }

    private static func simpleCSVRows(_ text: String) -> [[String: String]] {
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

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character == "\n", !quoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    @objc private func zoomIn() {
        #if canImport(GoogleMaps)
        if let googleMapView {
            googleMapView.animate(toZoom: googleMapView.camera.zoom + 1)
            return
        }
        #endif
    }

    @objc private func zoomOut() {
        #if canImport(GoogleMaps)
        if let googleMapView {
            googleMapView.animate(toZoom: googleMapView.camera.zoom - 1)
            return
        }
        #endif
    }

    #if canImport(GoogleMaps)
    private func addGoogleRouteMarkers(on mapView: GMSMapView) {
        let start = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let startMarker = GMSMarker(position: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
        startMarker.title = route == nil ? "현재 위치 대기" : "출발"
        startMarker.icon = makeRouteEndpointIcon(text: "출발", backgroundColor: .systemGreen)
        startMarker.opacity = 0.82
        startMarker.groundAnchor = CGPoint(x: 0.5, y: 1.0)
        startMarker.map = mapView
        googleRouteStartMarker = startMarker

        guard let end = route?.polyline.last ?? routes.first?.polyline.last,
              end != start else { return }
        let endMarker = GMSMarker(position: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude))
        endMarker.title = "도착"
        endMarker.icon = makeRouteEndpointIcon(text: "도착", backgroundColor: .systemRed)
        endMarker.opacity = 0.82
        endMarker.groundAnchor = CGPoint(x: 0.5, y: 1.0)
        endMarker.map = mapView
        googleRouteEndMarker = endMarker
    }

    private func addGoogleRiskMarkers(on mapView: GMSMapView) {
        addGoogleRiskMarkers(for: riskRoutes, on: mapView)
    }

    private func addGoogleRiskMarkers(for visibleRoutes: [Route], on mapView: GMSMapView) {
        let bundledSpots = Self.loadBundledSensorRiskSpots()
        let routeSpots = visibleRoutes.flatMap(\.riskCells).compactMap { cell -> SensorRiskSpot? in
            guard !cell.id.contains("sensor-2026-08-09"),
                  let coordinate = coordinate(fromRiskGeometry: cell.geometry) else { return nil }
            return SensorRiskSpot(
                id: cell.id,
                coordinate: coordinate,
                score: cell.riskScore,
                time: 0,
                decision: "충격 이벤트 후보",
                isVideoSupported: true
            )
        }
        let spots = bundledSpots + routeSpots
        var seen = Set<String>()
        var addedCount = 0
        for spot in spots where seen.insert(spot.id).inserted {
            let coordinate = nearestRouteCoordinate(to: spot.coordinate, in: visibleRoutes, maximumDistanceMeters: 90) ?? spot.coordinate
            let position = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let color = spot.isVideoSupported ? UIColor(red: CGFloat(0xff) / 255, green: CGFloat(0x6b) / 255, blue: CGFloat(0x66) / 255, alpha: 1) : UIColor(red: CGFloat(0xf6) / 255, green: CGFloat(0xb8) / 255, blue: CGFloat(0x4b) / 255, alpha: 1)
            let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            marker.title = spot.isVideoSupported ? "영상 확인 후보" : "센서 단독 후보"
            let timeText = spot.time > 0 ? " · \(Self.durationText(spot.time))" : ""
            marker.snippet = "\(spot.decision)\(timeText) · 상대 노면 점수 \(Int(spot.score.rounded()))점"
            marker.icon = makeRiskSpotIcon(fillColor: color)
            marker.opacity = spot.isVideoSupported ? 0.72 : 0.64
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.zIndex = 260
            marker.map = mapView
            googleRiskMarkers.append(marker)
            addedCount += 1
        }
        print("R2D risk markers added:", addedCount)
    }

    private func replaceGoogleRiskMarkers(for visibleRoutes: [Route]) {
        guard let mapView = googleMapView else { return }
        googleRiskMarkers.forEach { $0.map = nil }
        googleRiskMarkers.removeAll()
        googleRiskCircles.forEach { $0.map = nil }
        googleRiskCircles.removeAll()
        addGoogleRiskMarkers(for: visibleRoutes, on: mapView)
    }

    private func addGoogleRoutePolyline(on mapView: GMSMapView) {
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        for (index, value) in visibleRoutes.enumerated() {
            guard value.polyline.count >= 2 else { continue }
            let path = GMSMutablePath()
            let displayPolyline = displayPolyline(for: value, routeIndex: index, totalRoutes: visibleRoutes.count)
            for point in displayPolyline {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            let polyline = GMSPolyline(path: path)
            let color = routeColor(for: value, index: index)
            let isSelected = value.id == selectedRouteID || (selectedRouteID == nil && index == 0)
            let isSensorRoute = value.providerOption == "sensor_logger"
            polyline.strokeWidth = isSensorRoute ? 3 : (isSelected ? 8 : 5)
            polyline.strokeColor = isSensorRoute ? UIColor.white.withAlphaComponent(0.72) : color.withAlphaComponent(isSelected ? 0.95 : 0.50)
            polyline.geodesic = true
            polyline.zIndex = isSensorRoute ? 90 : Int32(isSelected ? 150 : 100 + index)
            polyline.isTappable = true
            polyline.userData = value.id
            polyline.map = mapView
            googleRoutePolylineMap[value.id] = polyline
            googleRouteIndexMap[value.id] = index
            googleRoutePolylines.append(polyline)
        }
    }

    private func addGoogleScoreSegments(on mapView: GMSMapView) {
        let shouldShowSensorScores = (route?.providerOption == "sensor_logger")
            || routes.contains { $0.providerOption == "sensor_logger" }
        guard shouldShowSensorScores else { return }
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        let points = Self.loadBundledSensorScorePoints()
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            guard current.eligible, next.eligible else { continue }
            let currentCoordinate = nearestRouteCoordinate(to: current.coordinate, in: visibleRoutes, maximumDistanceMeters: 90) ?? current.coordinate
            let nextCoordinate = nearestRouteCoordinate(to: next.coordinate, in: visibleRoutes, maximumDistanceMeters: 90) ?? next.coordinate
            let path = GMSMutablePath()
            path.add(.init(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude))
            path.add(.init(latitude: nextCoordinate.latitude, longitude: nextCoordinate.longitude))
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 11
            polyline.strokeColor = Self.roadScoreColor(current.score).withAlphaComponent(current.confidence < 0.7 ? 0.62 : 0.96)
            polyline.geodesic = true
            polyline.zIndex = 320
            polyline.map = mapView
            googleScoreSegmentPolylines.append(polyline)
        }
    }

    private func fitGoogleCameraToRoute(on mapView: GMSMapView) {
        let routeCoordinates = routes.flatMap(\.polyline).isEmpty ? route?.polyline ?? [] : routes.flatMap(\.polyline)
        let mapMatchCoordinates = matchedTrace.flatMap { [$0.original, $0.matched] }
        let riskCoordinates = (riskRoutes.flatMap(\.riskCells) + Self.loadBundledSensorRiskCells()).compactMap { coordinate(fromRiskGeometry: $0.geometry) }
        let coordinates = routeCoordinates + mapMatchCoordinates + riskCoordinates
        guard coordinates.count >= 2 else { return }
        var bounds = GMSCoordinateBounds()
        for coordinate in coordinates {
            bounds = bounds.includingCoordinate(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let update = GMSCameraUpdate.fit(bounds, withPadding: 42)
        mapView.moveCamera(update)
    }

    private func addGoogleMapMatchOverlay(on mapView: GMSMapView) {
        guard matchedTrace.count >= 2 else { return }

        let originalPath = GMSMutablePath()
        let matchedPath = GMSMutablePath()
        for point in matchedTrace {
            originalPath.add(.init(latitude: point.original.latitude, longitude: point.original.longitude))
            matchedPath.add(.init(latitude: point.matched.latitude, longitude: point.matched.longitude))
        }

        let originalPolyline = GMSPolyline(path: originalPath)
        originalPolyline.strokeColor = UIColor.white.withAlphaComponent(0.28)
        originalPolyline.strokeWidth = 4
        originalPolyline.geodesic = true
        originalPolyline.zIndex = 170
        originalPolyline.map = mapView
        googleOriginalTracePolyline = originalPolyline

        let matchedPolyline = GMSPolyline(path: matchedPath)
        matchedPolyline.strokeColor = UIColor.systemCyan.withAlphaComponent(0.95)
        matchedPolyline.strokeWidth = 6
        matchedPolyline.geodesic = true
        matchedPolyline.zIndex = 190
        matchedPolyline.map = mapView
        googleMatchedTracePolyline = matchedPolyline

        let highlighted = matchedTrace.filter {
            visualDistance($0.original, $0.matched) >= 8
        }.prefix(12)

        for point in highlighted {
            let marker = GMSMarker(position: .init(latitude: point.matched.latitude, longitude: point.matched.longitude))
            marker.title = "맵매칭 보정"
            marker.snippet = "원본 대비 \(Int(point.distanceFromOriginalM.rounded()))m"
            marker.icon = makeMapMatchBadgeIcon()
            marker.map = mapView
            googleMapMatchDebugMarkers.append(marker)
        }
    }

    private func refreshGoogleRoutePolylineStyles() {
        for (index, value) in routes.enumerated() {
            guard let polyline = googleRoutePolylineMap[value.id] else { continue }
            let isSelected = value.id == selectedRouteID
            let isSensorRoute = value.providerOption == "sensor_logger"
            polyline.strokeWidth = isSensorRoute ? 3 : (isSelected ? 8 : 5)
            polyline.strokeColor = isSensorRoute ? UIColor.white.withAlphaComponent(0.72) : routeColor(for: value, index: index).withAlphaComponent(isSelected ? 0.95 : 0.50)
            polyline.zIndex = Int32(isSensorRoute ? 90 : (isSelected ? 150 : 100 + index))
        }
    }

    private func updateGoogleUserLocationMarker(_ location: CLLocation) {
        guard let mapView = googleMapView else { return }
        let position = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        if let marker = googleUserLocationMarker {
            marker.position = position
        } else {
            let marker = GMSMarker(position: position)
            marker.title = "내 위치"
            marker.icon = makeCurrentLocationDotIcon()
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.opacity = 0.78
            marker.map = mapView
            googleUserLocationMarker = marker
        }

        guard followsUserLocation, !didCenterOnUserLocation else { return }
        didCenterOnUserLocation = true
        mapView.animate(toLocation: position)
    }

    private func makeRouteEndpointIcon(text: String, backgroundColor: UIColor) -> UIImage? {
        let size = CGSize(width: 42, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bubbleRect = CGRect(x: 4, y: 1, width: 34, height: 21)
            let bubble = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 10.5)
            backgroundColor.withAlphaComponent(0.82).setFill()
            bubble.fill()

            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: 21, y: 31))
            tail.addLine(to: CGPoint(x: 16, y: 22))
            tail.addLine(to: CGPoint(x: 26, y: 22))
            tail.close()
            backgroundColor.withAlphaComponent(0.82).setFill()
            tail.fill()

            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.72).cgColor)
            context.cgContext.setLineWidth(1)
            bubble.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.96),
                .paragraphStyle: paragraph
            ]
            (text as NSString).draw(in: CGRect(x: 4, y: 5, width: 34, height: 13), withAttributes: attributes)
        }
    }

    private func makeBikeMarkerIcon(tintColor: UIColor, backgroundColor: UIColor) -> UIImage? {
        let pinSize = CGSize(width: 44, height: 56)
        let renderer = UIGraphicsImageRenderer(size: pinSize)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: pinSize)
            let bubbleRect = CGRect(x: 4, y: 4, width: 36, height: 36)
            let bubblePath = UIBezierPath(ovalIn: bubbleRect)
            backgroundColor.setFill()
            bubblePath.fill()

            let tailPath = UIBezierPath()
            tailPath.move(to: CGPoint(x: pinSize.width / 2, y: 52))
            tailPath.addLine(to: CGPoint(x: 16, y: 28))
            tailPath.addLine(to: CGPoint(x: 28, y: 28))
            tailPath.close()
            backgroundColor.setFill()
            tailPath.fill()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            let symbol = UIImage(systemName: "bicycle", withConfiguration: symbolConfig)?
                .withTintColor(tintColor, renderingMode: .alwaysOriginal)
            let symbolRect = CGRect(x: 11, y: 11, width: 22, height: 22)
            symbol?.draw(in: symbolRect)

            context.cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.16).cgColor)
            context.cgContext.setLineWidth(1)
            let outline = UIBezierPath(ovalIn: bubbleRect)
            outline.stroke()
        }
    }

    private func makeCurrentLocationDotIcon() -> UIImage? {
        let size = CGSize(width: 18, height: 18)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let outer = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.72).setFill()
            outer.fill()

            let inner = UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 10, height: 10))
            UIColor.systemBlue.withAlphaComponent(0.82).setFill()
            inner.fill()

            context.cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
            context.cgContext.setLineWidth(1)
            outer.stroke()
        }
    }

    private func makeMapMatchBadgeIcon() -> UIImage? {
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            UIColor.systemCyan.setFill()
            circle.fill()
            let inner = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 10, height: 10))
            UIColor.white.setFill()
            inner.fill()
        }
    }

    private func makeRiskSpotIcon(fillColor: UIColor) -> UIImage? {
        let size = CGSize(width: 14, height: 14)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let outer = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.58).setFill()
            outer.fill()
            let inner = UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 8, height: 8))
            fillColor.withAlphaComponent(0.82).setFill()
            inner.fill()
        }
    }
    #endif

    #if canImport(iNaviMaps)
    private func configureMapView(_ mapView: InaviMapView) {
        mapView.delegate = self
        mapView.mapType = .normal

        mapView.showCompass = true
        mapView.showScaleBar = true
        mapView.showZoomControl = true
        mapView.showLocationButton = true

        mapView.isScrollGesturesEnabled = true
        mapView.isZoomGesturesEnabled = true
        mapView.isRotateGesturesEnabled = false
        mapView.isTiltGesturesEnabled = false

        mapView.userTrackingMode = .tracking

        let center = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let cameraUpdate = INVCameraUpdate(targetTo: INVLatLng(lat: center.latitude, lng: center.longitude))
        cameraUpdate.animation = .easeOut
        cameraUpdate.animationDuration = 1
        mapView.moveCamera(cameraUpdate)
    }

    private func logCoordinateConversionSample() {
        let wgs84 = INVLatLng(lat: Self.defaultCenter.latitude, lng: Self.defaultCenter.longitude)
        let converted = R2DCoordinateConverter.convertFromWGS84(wgs84)
        let utmkToWGS84 = R2DCoordinateConverter.utmkToWGS84(x: converted.utmk.x, y: converted.utmk.y)

        print(
            "R2D coordinate conversion:",
            "KATEC(\(converted.katec.x), \(converted.katec.y))",
            "UTMK(\(converted.utmk.x), \(converted.utmk.y))",
            "TM(\(converted.tm.x), \(converted.tm.y))",
            "GRS80(\(converted.grs80.x), \(converted.grs80.y))",
            "UTMK->WGS84(\(utmkToWGS84.lat), \(utmkToWGS84.lng))"
        )
    }

    private func addRouteMarkers(on mapView: InaviMapView) {
        let start = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let startMarker = INVMarker()
        startMarker.position = INVLatLng(lat: start.latitude, lng: start.longitude)
        startMarker.title = route == nil ? "현재 위치 대기" : "출발"
        startMarker.touchEvent = { _ in
            print("R2D route marker tapped")
            return true
        }
        startMarker.mapView = mapView
        routeStartMarker = startMarker

        guard let end = route?.polyline.last ?? routes.first?.polyline.last, end != start else { return }
        let endMarker = INVMarker()
        endMarker.position = INVLatLng(lat: end.latitude, lng: end.longitude)
        endMarker.title = "도착"
        endMarker.mapView = mapView
        routeEndMarker = endMarker
    }

    private func addRiskMarkers(on mapView: InaviMapView) {
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        let bundledSpots = Self.loadBundledSensorRiskSpots()
        let routeSpots = visibleRoutes.flatMap(\.riskCells).compactMap { cell -> SensorRiskSpot? in
            guard !cell.id.contains("sensor-2026-08-09"),
                  let coordinate = coordinate(fromRiskGeometry: cell.geometry) else { return nil }
            return SensorRiskSpot(id: cell.id, coordinate: coordinate, score: cell.riskScore, time: 0, decision: "충격 이벤트 후보", isVideoSupported: true)
        }
        for spot in bundledSpots + routeSpots {
            let coordinate = nearestRouteCoordinate(to: spot.coordinate, in: visibleRoutes, maximumDistanceMeters: 90) ?? spot.coordinate
            let marker = INVMarker()
            marker.position = INVLatLng(lat: coordinate.latitude, lng: coordinate.longitude)
            marker.title = "\(spot.isVideoSupported ? "영상 확인 후보" : "센서 단독 후보") · \(spot.decision) · \(Int(spot.score.rounded()))점"
            marker.touchEvent = { _ in
                print("R2D risk spot tapped:", spot.id)
                return true
            }
            marker.mapView = mapView
            riskMarkers.append(marker)
        }
    }

    private func addRoutePolyline(on mapView: InaviMapView) {
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        for (index, value) in visibleRoutes.enumerated() {
            guard value.polyline.count >= 2 else { continue }
            let displayPolyline = displayPolyline(for: value, routeIndex: index, totalRoutes: visibleRoutes.count)
            let points = displayPolyline.map { INVLatLng(lat: $0.latitude, lng: $0.longitude) }
            let polyline = INVPolyline(coords: points)
            let color = routeColor(for: value, index: index)
            let isSelected = value.id == selectedRouteID || (selectedRouteID == nil && index == 0)
            let isSensorRoute = value.providerOption == "sensor_logger"
            polyline.width = isSensorRoute ? 3 : (isSelected ? 8 : 5)
            polyline.color = isSensorRoute ? UIColor.white.withAlphaComponent(0.72) : color.withAlphaComponent(isSelected ? 0.95 : 0.62)
            polyline.capType = .round
            polyline.joinType = .round
            polyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + (isSensorRoute ? 90 : (isSelected ? 150 : 100 + index))
            polyline.touchEvent = { [weak self] _ in
                self?.selectRoute(value)
                return true
            }
            polyline.mapView = mapView
            routePolylines.append(polyline)
            routePolylineMap[value.id] = polyline
            routePolylineIndexMap[value.id] = index
        }
    }

    private func addScoreSegments(on mapView: InaviMapView) {
        let shouldShowSensorScores = (route?.providerOption == "sensor_logger")
            || routes.contains { $0.providerOption == "sensor_logger" }
        guard shouldShowSensorScores else { return }
        let visibleRoutes = routes.isEmpty ? route.map { [$0] } ?? [] : routes
        let points = Self.loadBundledSensorScorePoints()
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            guard current.eligible, next.eligible else { continue }
            let currentCoordinate = nearestRouteCoordinate(to: current.coordinate, in: visibleRoutes, maximumDistanceMeters: 90) ?? current.coordinate
            let nextCoordinate = nearestRouteCoordinate(to: next.coordinate, in: visibleRoutes, maximumDistanceMeters: 90) ?? next.coordinate
            let polyline = INVPolyline(coords: [
                INVLatLng(lat: currentCoordinate.latitude, lng: currentCoordinate.longitude),
                INVLatLng(lat: nextCoordinate.latitude, lng: nextCoordinate.longitude)
            ])
            polyline.width = 9
            polyline.color = Self.roadScoreColor(current.score).withAlphaComponent(current.confidence < 0.7 ? 0.46 : 0.94)
            polyline.capType = .round
            polyline.joinType = .round
            polyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + 220
            polyline.mapView = mapView
            scoreSegmentPolylines.append(polyline)
        }
    }

    private func refreshRoutePolylineStyles() {
        for (index, value) in routes.enumerated() {
            guard let polyline = routePolylineMap[value.id] else { continue }
            let isSelected = value.id == selectedRouteID
            let isSensorRoute = value.providerOption == "sensor_logger"
            polyline.width = isSensorRoute ? 3 : (isSelected ? 8 : 5)
            polyline.color = isSensorRoute ? UIColor.white.withAlphaComponent(0.72) : routeColor(for: value, index: index).withAlphaComponent(isSelected ? 0.95 : 0.62)
            polyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + (isSensorRoute ? 90 : (isSelected ? 150 : 100 + index))
        }
    }

    private func fitCameraToRoute(on mapView: InaviMapView) {
        let routeCoordinates = routes.flatMap(\.polyline).isEmpty ? route?.polyline ?? [] : routes.flatMap(\.polyline)
        let mapMatchCoordinates = matchedTrace.flatMap { [$0.original, $0.matched] }
        let coordinates = routeCoordinates + mapMatchCoordinates
        guard coordinates.count >= 2 else { return }
        let points = coordinates.map { INVLatLng(lat: $0.latitude, lng: $0.longitude) }
        let bounds = INVLatLngBounds(coords: points)
        let cameraUpdate = INVCameraUpdate(fit: bounds, paddingInsets: UIEdgeInsets(top: 90, left: 42, bottom: 90, right: 42))
        cameraUpdate.animation = .easeOut
        cameraUpdate.animationDuration = 0.9
        mapView.moveCamera(cameraUpdate)
    }

    private func addMapMatchOverlay(on mapView: InaviMapView) {
        guard matchedTrace.count >= 2 else { return }

        let originalPoints = matchedTrace.map { INVLatLng(lat: $0.original.latitude, lng: $0.original.longitude) }
        let matchedPoints = matchedTrace.map { INVLatLng(lat: $0.matched.latitude, lng: $0.matched.longitude) }

        let originalPolyline = INVPolyline(coords: originalPoints)
        originalPolyline.width = 4
        originalPolyline.color = UIColor.white.withAlphaComponent(0.28)
        originalPolyline.capType = .round
        originalPolyline.joinType = .round
        originalPolyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + 160
        originalPolyline.mapView = mapView
        self.originalTracePolyline = originalPolyline

        let matchedPolyline = INVPolyline(coords: matchedPoints)
        matchedPolyline.width = 6
        matchedPolyline.color = UIColor.systemCyan.withAlphaComponent(0.95)
        matchedPolyline.capType = .round
        matchedPolyline.joinType = .round
        matchedPolyline.globalZIndex = Int(INV_POLYLINE_DEFAULT_GLOBAL_Z_INDEX) + 180
        matchedPolyline.mapView = mapView
        self.matchedTracePolyline = matchedPolyline

        let highlighted = matchedTrace.filter {
            visualDistance($0.original, $0.matched) >= 8
        }.prefix(12)

        for point in highlighted {
            let marker = INVMarker()
            marker.position = INVLatLng(lat: point.matched.latitude, lng: point.matched.longitude)
            marker.title = "보정 \(Int(point.distanceFromOriginalM.rounded()))m"
            marker.mapView = mapView
            mapMatchDebugMarkers.append(marker)
        }
    }

    private func configureInfoWindow(on mapView: InaviMapView) {
        guard let marker = routeStartMarker else { return }

        let infoWindow = INVInfoWindow()
        infoWindow.imageDataSource = infoWindowDataSource
        infoWindow.alpha = 0.95
        infoWindow.marker = marker
        infoWindow.mapView = mapView
        routeStartInfoWindow = infoWindow
    }

    private func configureClusterManager(on mapView: InaviMapView) {
        let manager = INVClusterManager(mapView: mapView)
        manager.delegate = self
        manager.minClusteringCount = 2
        manager.maxDistanceBetweenItems = 120

        let start = route?.polyline.first ?? routes.first?.polyline.first ?? initialCurrentLocation ?? Self.defaultCenter
        let end = route?.polyline.last ?? routes.first?.polyline.last
        var items = [
            R2DClusterItem(position: INVLatLng(lat: start.latitude, lng: start.longitude), title: "출발 지점"),
            R2DClusterItem(position: INVLatLng(lat: 37.237300, lng: 127.037120), title: "노면 후보 1"),
            R2DClusterItem(position: INVLatLng(lat: 37.238100, lng: 127.038200), title: "노면 후보 2"),
            R2DClusterItem(position: INVLatLng(lat: 37.232950, lng: 127.032900), title: "주의 구간"),
            R2DClusterItem(position: INVLatLng(lat: 37.230900, lng: 127.034400), title: "센서 이벤트")
        ]
        if let end {
            items.append(R2DClusterItem(position: INVLatLng(lat: end.latitude, lng: end.longitude), title: "도착 지점"))
        }

        manager.add(items)
        clusterItems = items
        clusterManager = manager
    }

    private func updateUserLocationMarker(_ location: CLLocation) {
        guard let mapView else { return }
        let position = INVLatLng(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        if let marker = userLocationMarker {
            marker.position = position
        } else {
            let marker = INVMarker()
            marker.position = position
            marker.title = "자전거 현재 위치"
            marker.mapView = mapView
            userLocationMarker = marker
        }

        guard followsUserLocation, !didCenterOnUserLocation else { return }
        didCenterOnUserLocation = true
        let cameraUpdate = INVCameraUpdate(targetTo: position)
        cameraUpdate.animation = .easeOut
        cameraUpdate.animationDuration = 0.8
        mapView.moveCamera(cameraUpdate)
    }
    #endif

    private func bindRideStateIfNeeded() {
        guard let rideStateProvider else { return }
        rideStateUnsubscribe?()
        rideStateUnsubscribe = rideStateProvider.subscribe { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyRideState(state)
            }
        }
    }

    @MainActor
    private func applyRideState(_ state: ActiveRideState) {
        #if canImport(GoogleMaps)
        if let coordinate = state.mapState.currentLocation ?? state.location.coordinate {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            updateGoogleUserLocationMarker(location)
        }

        if let selectedRoute = state.selectedRoute, selectedRoute.id != selectedRouteID {
            selectedRouteID = selectedRoute.id
            refreshGoogleRoutePolylineStyles()
            replaceGoogleRiskMarkers(for: riskRoutes)
        }

        if followsUserLocation, let camera = state.mapState.camera, let mapView = googleMapView {
            let update = GMSCameraUpdate.setTarget(
                CLLocationCoordinate2D(latitude: camera.center.latitude, longitude: camera.center.longitude),
                zoom: mapView.camera.zoom
            )
            mapView.animate(with: update)
        }
        #endif
        #if canImport(iNaviMaps)
        guard let mapView else { return }

        if let coordinate = state.mapState.currentLocation ?? state.location.coordinate {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            updateUserLocationMarker(location)
        }

        if let selectedRoute = state.selectedRoute, selectedRoute.id != selectedRouteID {
            selectedRouteID = selectedRoute.id
            refreshRoutePolylineStyles()
        }

        guard followsUserLocation, let camera = state.mapState.camera else { return }
        let cameraUpdate = INVCameraUpdate(
            targetTo: INVLatLng(lat: camera.center.latitude, lng: camera.center.longitude)
        )
        cameraUpdate.animation = .linear
        cameraUpdate.animationDuration = 0.6
        mapView.moveCamera(cameraUpdate)
        #endif
    }

    private func startUserLocationUpdates() {
        guard followsUserLocation else { return }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionMessage()
        @unknown default:
            break
        }
    }

    private func showLocationPermissionMessage() {
        let alert = UIAlertController(title: "위치 권한 필요", message: "지도에서 실시간 내 위치를 보려면 위치 권한을 허용해 주세요.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func displayPolyline(for route: Route, routeIndex: Int, totalRoutes: Int) -> [Coordinate] {
        guard totalRoutes > 1 else { return route.polyline }
        let offsetMeters = lateralOffsetMeters(for: route.providerOption, routeIndex: routeIndex)
        guard abs(offsetMeters) > 0.1 else { return route.polyline }
        return shiftedPolyline(route.polyline, lateralOffsetMeters: offsetMeters)
    }

    private func lateralOffsetMeters(for option: String?, routeIndex: Int) -> Double {
        switch option {
        case "sensor_logger":
            return 0
        case "pm", "pm_recommendation":
            return 0
        case "pm_main_road":
            return 10
        case "pm_short_distance_priority":
            return -10
        default:
            let centeredIndex = Double(routeIndex) - Double(max(routes.count - 1, 0)) / 2
            return centeredIndex * 8
        }
    }

    private func routeColor(for route: Route, index: Int) -> UIColor {
        if route.providerOption == "sensor_logger" {
            return .systemPurple
        }
        let colors: [UIColor] = [.systemYellow, .systemGreen, .systemBlue, .systemTeal, .systemPink]
        return colors[index % colors.count]
    }

    private static func roadScoreColor(_ score: Double) -> UIColor {
        if score >= 80 { return UIColor(red: CGFloat(0x27) / 255, green: CGFloat(0xd7) / 255, blue: CGFloat(0xad) / 255, alpha: 1) }
        if score >= 65 { return UIColor(red: CGFloat(0xb8) / 255, green: CGFloat(0xdd) / 255, blue: CGFloat(0x50) / 255, alpha: 1) }
        if score >= 50 { return UIColor(red: CGFloat(0xf6) / 255, green: CGFloat(0xb8) / 255, blue: CGFloat(0x4b) / 255, alpha: 1) }
        return UIColor(red: CGFloat(0xff) / 255, green: CGFloat(0x6b) / 255, blue: CGFloat(0x66) / 255, alpha: 1)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        let minutes = rounded / 60
        let remainingSeconds = rounded % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    private func shiftedPolyline(_ coordinates: [Coordinate], lateralOffsetMeters: Double) -> [Coordinate] {
        guard coordinates.count >= 2 else { return coordinates }
        var shifted: [Coordinate] = []
        shifted.reserveCapacity(coordinates.count)

        for index in coordinates.indices {
            let current = coordinates[index]
            let previous = coordinates[max(0, index - 1)]
            let next = coordinates[min(coordinates.count - 1, index + 1)]
            let heading = headingDegrees(from: previous, to: next)
            shifted.append(offsetCoordinate(current, headingDegrees: heading + 90, distanceMeters: lateralOffsetMeters))
        }

        return shifted
    }

    private func headingDegrees(from start: Coordinate, to end: Coordinate) -> Double {
        let delta = (end.longitude - start.longitude) * .pi / 180
        let latitudeA = start.latitude * .pi / 180
        let latitudeB = end.latitude * .pi / 180
        let y = sin(delta) * cos(latitudeB)
        let x = cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func offsetCoordinate(_ coordinate: Coordinate, headingDegrees: Double, distanceMeters: Double) -> Coordinate {
        let radians = headingDegrees * .pi / 180
        let dLat = (distanceMeters * cos(radians)) / 111_320
        let metersPerLng = max(1, 111_320 * cos(coordinate.latitude * .pi / 180))
        let dLng = (distanceMeters * sin(radians)) / metersPerLng
        return Coordinate(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLng)
    }

    private func visualDistance(_ start: Coordinate, _ end: Coordinate) -> Double {
        let dy = (end.latitude - start.latitude) * 111_320
        let dx = (end.longitude - start.longitude) * 111_320 * cos(start.latitude * .pi / 180)
        return sqrt(dx * dx + dy * dy)
    }

    private func coordinate(fromRiskGeometry geometry: String) -> Coordinate? {
        guard geometry.hasPrefix("POINT("), geometry.hasSuffix(")") else { return nil }
        let body = geometry
            .dropFirst("POINT(".count)
            .dropLast()
            .split(separator: " ")
        guard body.count == 2, let first = Double(body[0]), let second = Double(body[1]) else { return nil }
        if abs(first) <= 90, abs(second) <= 180 {
            return Coordinate(latitude: first, longitude: second)
        }
        if abs(second) <= 90, abs(first) <= 180 {
            return Coordinate(latitude: second, longitude: first)
        }
        return nil
    }
}

private enum ElevationError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponse
}

private struct ElevationResponse: Decodable {
    let results: [ElevationResult]
    let status: String
}

private struct ElevationResult: Decodable {
    let elevation: Double
}

#if canImport(iNaviMaps)
private final class R2DInfoWindowDataSource: NSObject, INVImageTextDataSource {
    nonisolated func title(with shape: INVShape) -> String {
        if let infoWindow = shape as? INVInfoWindow {
            return String(format: "R2D 출발 지점\n%.5f, %.5f", infoWindow.position.lat, infoWindow.position.lng)
        }
        return "R2D 정보"
    }
}

private final class R2DClusterItem: NSObject, INVClusterItem {
    let position: INVLatLng
    let title: String

    init(position: INVLatLng, title: String) {
        self.position = position
        self.title = title
        super.init()
    }
}

extension R2DMapViewController: @preconcurrency INVMapViewDelegate {
    nonisolated public func mapView(_ mapView: InaviMapView, didUpdateUserLocation userLocation: CLLocation?) {
        guard let location = userLocation else { return }
        print("R2D user location:", location.coordinate.latitude, location.coordinate.longitude)
    }
}

extension R2DMapViewController: @preconcurrency INVClusterManagerDelegate {
    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, willRender cluster: INVCluster, with markerOptions: INVMarkerOptions) {
        markerOptions.position = cluster.position
        markerOptions.title = "\(cluster.count)"
        markerOptions.titleColor = .white
        markerOptions.titleHaloColor = .systemBlue
        markerOptions.titleSize = 14
    }

    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, willRenderClusterItem clusterItem: INVClusterItem, with markerOptions: INVMarkerOptions) {
        markerOptions.position = clusterItem.position
        if let item = clusterItem as? R2DClusterItem {
            markerOptions.title = item.title
        }
        markerOptions.titleColor = .black
        markerOptions.titleHaloColor = .white
        markerOptions.titleSize = 12
    }

    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, didTap cluster: INVCluster, with markerOptions: INVMarkerOptions) -> Bool {
        print("R2D cluster tapped:", cluster.count)
        return true
    }

    nonisolated public func clusterManager(_ clusterManager: INVClusterManager, didTap clusterItem: INVClusterItem, with markerOptions: INVMarkerOptions) -> Bool {
        if let item = clusterItem as? R2DClusterItem {
            print("R2D cluster item tapped:", item.title)
        }
        return true
    }
}
#endif

extension R2DMapViewController: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionMessage()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        #if canImport(GoogleMaps)
        updateGoogleUserLocationMarker(location)
        #endif
        #if canImport(iNaviMaps)
        updateUserLocationMarker(location)
        #endif
    }
}

#if canImport(GoogleMaps)
extension R2DMapViewController: @preconcurrency GMSMapViewDelegate {
    public func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
        inspectRouteIfNeeded(at: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    public func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
        guard let polyline = overlay as? GMSPolyline,
              let routeID = polyline.userData as? String,
              let route = routes.first(where: { $0.id == routeID }) else { return }
        selectRoute(route)
        if let coordinate = route.polyline.first {
            inspectCoordinate(coordinate)
        }
    }
}
#endif
#endif

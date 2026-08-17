#if canImport(UIKit) && canImport(WebKit)
import CoreLocation
import Foundation
import R2DAppSupport
import R2DCore
import R2DInfrastructure
import UIKit
import WebKit

public final class R2DOSMRideMapViewController: UIViewController {
    private struct ScorePoint: Codable {
        let time: TimeInterval
        let latitude: Double
        let longitude: Double
        let score: Double
        let eligible: Bool
    }

    private struct EventPoint: Codable {
        let id: String
        let time: TimeInterval
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let score: Double
        let evidence: String
        let decision: String
    }

    private struct RoutePayload: Codable {
        let id: String
        let name: String
        let coordinates: [[Double]]
    }

    private struct Payload: Codable {
        let route: RoutePayload
        let scorePoints: [ScorePoint]
        let events: [EventPoint]
        let currentLocation: [Double]?
    }

    private let route: Route
    private let rideStateProvider: ActiveRideCoordinator?
    private let initialCurrentLocation: Coordinate?
    private let webView: WKWebView
    private let closeButton = UIButton(type: .system)
    private var rideStateUnsubscribe: Unsubscribe?
    private var didLoadPage = false
    private var pendingCoordinate: Coordinate?

    public init(
        route: Route,
        initialCurrentLocation: Coordinate? = nil,
        rideStateProvider: ActiveRideCoordinator? = nil
    ) {
        self.route = route
        self.initialCurrentLocation = initialCurrentLocation
        self.rideStateProvider = rideStateProvider
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.07, blue: 0.07, alpha: 1)
        configureWebView()
        configureCloseButton()
        bindRideState()
        loadHTML()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    deinit {
        rideStateUnsubscribe?()
    }

    private func configureWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.layer.cornerRadius = 27
        closeButton.layer.cornerCurve = .continuous
        closeButton.backgroundColor = UIColor(red: 0.03, green: 0.11, blue: 0.10, alpha: 0.82)
        closeButton.tintColor = .white
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 54),
            closeButton.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    private func bindRideState() {
        rideStateUnsubscribe = rideStateProvider?.subscribe { [weak self] state in
            guard let self, let coordinate = state.location.coordinate else { return }
            DispatchQueue.main.async {
                self.updateCurrentLocation(coordinate)
            }
        }
    }

    private func loadHTML() {
        webView.loadHTMLString(makeHTML(), baseURL: URL(string: "https://localhost/"))
    }

    private func makePayload() -> Payload {
        let scorePoints = Self.loadBundledScorePoints()
        let events = Self.loadBundledEvents()
        let current = initialCurrentLocation.map { [$0.latitude, $0.longitude] }
        return Payload(
            route: RoutePayload(
                id: route.id,
                name: Self.displayName(for: route),
                coordinates: route.polyline.map { [$0.latitude, $0.longitude] }
            ),
            scorePoints: scorePoints,
            events: events,
            currentLocation: current
        )
    }

    private func makeHTML() -> String {
        let payload = Self.jsonString(makePayload())
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <link href="https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css" rel="stylesheet">
          <script src="https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js"></script>
          <style>
            html, body, #map {
              height: 100%;
              width: 100%;
              margin: 0;
              background: #071716;
              font-family: "Apple SD Gothic Neo", "Noto Sans CJK KR", -apple-system, BlinkMacSystemFont, sans-serif;
            }
            #map canvas { outline: none; }
            .maplibregl-ctrl-top-right { margin-top: 88px; }
            .maplibregl-ctrl-bottom-right { margin-bottom: 88px; }
            .maplibregl-ctrl-attrib { color: #2d4a45; font-size: 10px; }
            .camera-panel {
              position: absolute;
              right: 12px;
              top: max(16px, env(safe-area-inset-top));
              z-index: 10;
              display: grid;
              gap: 6px;
              width: min(206px, calc(100vw - 112px));
              padding: 8px;
              border: 1px solid rgba(7, 23, 22, .25);
              border-radius: 8px;
              background: rgba(244, 247, 246, .94);
              color: #17332f;
              box-shadow: 0 10px 26px rgba(0, 0, 0, .18);
              -webkit-backdrop-filter: blur(14px);
              backdrop-filter: blur(14px);
            }
            .map-mode, .preset-row {
              display: grid;
              grid-template-columns: 1fr 1fr;
              gap: 6px;
            }
            .preset-row { grid-template-columns: repeat(3, 1fr); }
            button {
              min-height: 30px;
              border: 1px solid rgba(23, 51, 47, .22);
              border-radius: 6px;
              background: rgba(255, 255, 255, .82);
              color: #17332f;
              font: 700 10px "Apple SD Gothic Neo", -apple-system, BlinkMacSystemFont, sans-serif;
            }
            button.active {
              border-color: #27d7ad;
              background: rgba(39, 215, 173, .16);
              color: #071716;
            }
            .axis-row {
              display: grid;
              grid-template-columns: 48px 1fr 34px;
              gap: 6px;
              align-items: center;
              font-size: 10px;
              font-weight: 700;
            }
            .axis-row output {
              text-align: right;
              font-variant-numeric: tabular-nums;
              color: #2d4a45;
            }
            input[type="range"] {
              width: 100%;
              accent-color: #27d7ad;
            }
            .map-popup {
              display: grid;
              gap: 4px;
              color: #eaf4f0;
              font: 700 12px "Apple SD Gothic Neo", -apple-system, BlinkMacSystemFont, sans-serif;
            }
            .map-popup small {
              color: #9db8b1;
              font-size: 10px;
            }
            .maplibregl-popup-content {
              border: 1px solid rgba(39, 215, 173, .5);
              border-radius: 7px;
              background: rgba(5, 24, 22, .96);
              box-shadow: 0 12px 30px rgba(0, 0, 0, .3);
              padding: 8px;
            }
            .maplibregl-popup-tip { border-top-color: rgba(5, 24, 22, .96); }
            .coordinate-banner {
              position: absolute;
              left: 12px;
              right: 12px;
              bottom: max(18px, env(safe-area-inset-bottom));
              z-index: 10;
              display: none;
              gap: 4px;
              padding: 10px 12px;
              border: 1px solid rgba(39, 215, 173, .42);
              border-radius: 9px;
              background: rgba(5, 24, 22, .9);
              color: #eaf4f0;
              box-shadow: 0 10px 26px rgba(0, 0, 0, .24);
              -webkit-backdrop-filter: blur(14px);
              backdrop-filter: blur(14px);
              pointer-events: none;
            }
            .coordinate-banner.visible { display: grid; }
            .coordinate-banner strong {
              font-size: 11px;
            }
            .coordinate-banner span {
              color: #b8cbc6;
              font: 700 11px "Apple SD Gothic Neo", -apple-system, BlinkMacSystemFont, ui-monospace, SFMono-Regular, Menlo, monospace;
              font-variant-numeric: tabular-nums;
              line-height: 1.45;
            }
            @media (max-width: 520px) {
              .camera-panel {
                width: min(206px, calc(100vw - 112px));
                padding: 8px;
              }
              .axis-row { grid-template-columns: 48px 1fr 34px; }
            }
          </style>
        </head>
        <body>
          <div id="map"></div>
          <div class="camera-panel" aria-label="지도 시점 조정">
            <div class="map-mode">
              <button id="streetButton" type="button">OSM</button>
              <button id="satelliteButton" type="button" class="active">항공사진</button>
            </div>
            <div class="preset-row">
              <button id="topButton" type="button">상공</button>
              <button id="obliqueButton" type="button" class="active">3D</button>
              <button id="routeButton" type="button">진행방향</button>
            </div>
            <label class="axis-row">
              <span>X 방향</span>
              <input id="bearingSlider" type="range" min="-180" max="180" value="-24">
              <output id="bearingValue">-24°</output>
            </label>
            <label class="axis-row">
              <span>Y 기울기</span>
              <input id="pitchSlider" type="range" min="0" max="75" value="52">
              <output id="pitchValue">52°</output>
            </label>
            <label class="axis-row">
              <span>Z 확대</span>
              <input id="zoomSlider" type="range" min="13" max="18" step=".1" value="15.8">
              <output id="zoomValue">15.8×</output>
            </label>
          </div>
          <div id="coordinateBanner" class="coordinate-banner" aria-live="polite">
            <strong>경로 위치</strong>
            <span id="coordinateText"></span>
          </div>
          <script>
            const data = \(payload);
            const route = Array.isArray(data.route.coordinates) ? data.route.coordinates : [];
            const routeLngLat = route.map(point => [point[1], point[0]]);
            const fallbackCenter = routeLngLat[0]
              || (data.scorePoints && data.scorePoints[0] ? [data.scorePoints[0].longitude, data.scorePoints[0].latitude] : null)
              || (data.currentLocation ? [data.currentLocation[1], data.currentLocation[0]] : null)
              || [127.1043303, 37.1848896];
            function scoreColor(score) {
              if (score >= 80) return '#27d7ad';
              if (score >= 65) return '#b8dd50';
              if (score >= 50) return '#f6b84b';
              return '#ff6b66';
            }
            function formatTime(seconds) {
              const value = Math.max(0, Math.round(seconds));
              return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
            }
            function circlePolygon(lng, lat, radiusMeters) {
              const points = [];
              const earth = 6378137;
              const latRad = lat * Math.PI / 180;
              for (let index = 0; index <= 64; index += 1) {
                const angle = index / 64 * Math.PI * 2;
                const dx = radiusMeters * Math.cos(angle);
                const dy = radiusMeters * Math.sin(angle);
                const nextLat = lat + (dy / earth) * 180 / Math.PI;
                const nextLng = lng + (dx / (earth * Math.cos(latRad))) * 180 / Math.PI;
                points.push([nextLng, nextLat]);
              }
              return { type: 'Feature', geometry: { type: 'Polygon', coordinates: [points] }, properties: {} };
            }
            function routeBearing() {
              if (routeLngLat.length < 2) return -24;
              const start = routeLngLat[Math.max(0, Math.floor(routeLngLat.length * .52))];
              const end = routeLngLat[Math.min(routeLngLat.length - 1, Math.floor(routeLngLat.length * .52) + 8)];
              const lon1 = start[0] * Math.PI / 180;
              const lon2 = end[0] * Math.PI / 180;
              const lat1 = start[1] * Math.PI / 180;
              const lat2 = end[1] * Math.PI / 180;
              const y = Math.sin(lon2 - lon1) * Math.cos(lat2);
              const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lon2 - lon1);
              return Math.atan2(y, x) * 180 / Math.PI;
            }
            function snapLngLatToRoute(lng, lat, maximumDistanceMeters = 90) {
              if (routeLngLat.length < 2) return [lng, lat];
              const metersPerLat = 111320;
              const metersPerLng = Math.max(1, 111320 * Math.cos(lat * Math.PI / 180));
              const px = lng * metersPerLng;
              const py = lat * metersPerLat;
              let best = null;
              for (let index = 0; index < routeLngLat.length - 1; index += 1) {
                const start = routeLngLat[index];
                const end = routeLngLat[index + 1];
                const ax = start[0] * metersPerLng;
                const ay = start[1] * metersPerLat;
                const bx = end[0] * metersPerLng;
                const by = end[1] * metersPerLat;
                const dx = bx - ax;
                const dy = by - ay;
                const lengthSquared = dx * dx + dy * dy;
                const t = lengthSquared === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared));
                const sx = ax + dx * t;
                const sy = ay + dy * t;
                const distance = Math.hypot(px - sx, py - sy);
                if (!best || distance < best.distance) {
                  best = {
                    lngLat: [sx / metersPerLng, sy / metersPerLat],
                    distance
                  };
                }
              }
              return best && best.distance <= maximumDistanceMeters ? best.lngLat : [lng, lat];
            }
            function nearestRoutePoint(screenPoint) {
              if (routeLngLat.length === 0) return null;
              if (routeLngLat.length === 1) {
                const projected = map.project(routeLngLat[0]);
                const distance = Math.hypot(screenPoint.x - projected.x, screenPoint.y - projected.y);
                return { lngLat: routeLngLat[0], distance };
              }
              let best = null;
              for (let index = 0; index < routeLngLat.length - 1; index += 1) {
                const aLngLat = routeLngLat[index];
                const bLngLat = routeLngLat[index + 1];
                const a = map.project(aLngLat);
                const b = map.project(bLngLat);
                const dx = b.x - a.x;
                const dy = b.y - a.y;
                const lengthSquared = dx * dx + dy * dy;
                const t = lengthSquared === 0
                  ? 0
                  : Math.max(0, Math.min(1, ((screenPoint.x - a.x) * dx + (screenPoint.y - a.y) * dy) / lengthSquared));
                const px = a.x + dx * t;
                const py = a.y + dy * t;
                const distance = Math.hypot(screenPoint.x - px, screenPoint.y - py);
                if (!best || distance < best.distance) {
                  const lng = aLngLat[0] + (bLngLat[0] - aLngLat[0]) * t;
                  const lat = aLngLat[1] + (bLngLat[1] - aLngLat[1]) * t;
                  best = { lngLat: [lng, lat], distance };
                }
              }
              return best;
            }
            function terrainText(lngLat) {
              if (typeof map.queryTerrainElevation !== 'function') return '고도 확인 불가';
              const elevation = map.queryTerrainElevation(lngLat, { exaggerated: false });
              if (typeof elevation !== 'number' || !Number.isFinite(elevation)) return '고도 계산 중';
              return `고도 ${elevation.toFixed(1)}m`;
            }

            const scoreFeatures = [];
            (data.scorePoints || []).slice(0, -1).forEach((point, index) => {
              const next = data.scorePoints[index + 1];
              const currentLngLat = snapLngLatToRoute(point.longitude, point.latitude);
              const nextLngLat = snapLngLatToRoute(next.longitude, next.latitude);
              scoreFeatures.push({
                type: 'Feature',
                geometry: { type: 'LineString', coordinates: [currentLngLat, nextLngLat] },
                properties: {
                  color: point.eligible ? scoreColor(point.score) : '#5f7772',
                  width: point.eligible ? 6 : 4,
                  opacity: point.eligible ? .9 : .42,
                  score: Math.round(point.score),
                  time: formatTime(point.time),
                  eligible: point.eligible
                }
              });
            });
            const eventFeatures = (data.events || []).map(event => {
              const isVideo = event.evidence === 'video';
              const snapped = snapLngLatToRoute(event.longitude, event.latitude);
              return {
                type: 'Feature',
                geometry: { type: 'Point', coordinates: snapped },
                properties: {
                  color: isVideo ? '#ff6b66' : '#f6b84b',
                  label: isVideo ? '영상 확인 후보' : '센서 단독 후보',
                  score: Math.round(event.score),
                  time: formatTime(event.time),
                  decision: event.decision
                }
              };
            });
            const accuracyFeatures = (data.events || []).map(event => {
              const snapped = snapLngLatToRoute(event.longitude, event.latitude);
              return circlePolygon(snapped[0], snapped[1], event.accuracy || 14);
            });
            const endpointFeatures = routeLngLat.length ? [
              { type: 'Feature', geometry: { type: 'Point', coordinates: routeLngLat[0] }, properties: { label: '기록 시작', color: '#f4f7f6' } },
              { type: 'Feature', geometry: { type: 'Point', coordinates: routeLngLat[routeLngLat.length - 1] }, properties: { label: '기록 종료', color: '#27d7ad' } }
            ] : [];

            const map = new maplibregl.Map({
              container: 'map',
              center: fallbackCenter,
              zoom: 15.8,
              pitch: 52,
              bearing: -24,
              maxPitch: 75,
              attributionControl: true,
              canvasContextAttributes: { antialias: true },
              style: {
                version: 8,
                sources: {
                  osm: {
                    type: 'raster',
                    tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
                    tileSize: 256,
                    maxzoom: 19,
                    attribution: '© OpenStreetMap contributors'
                  },
                  satellite: {
                    type: 'raster',
                    tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
                    tileSize: 256,
                    maxzoom: 19,
                    attribution: 'Imagery © Esri, Maxar, Earthstar Geographics'
                  }
                },
                layers: [
                  {
                    id: 'osm',
                    type: 'raster',
                    source: 'osm',
                    layout: { visibility: 'none' },
                    paint: {
                      'raster-saturation': -0.05,
                      'raster-contrast': 0.02
                    }
                  },
                  {
                    id: 'satellite',
                    type: 'raster',
                    source: 'satellite'
                  }
                ]
              }
            });
            map.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), 'bottom-right');

            const bearingSlider = document.getElementById('bearingSlider');
            const pitchSlider = document.getElementById('pitchSlider');
            const zoomSlider = document.getElementById('zoomSlider');
            const bearingValue = document.getElementById('bearingValue');
            const pitchValue = document.getElementById('pitchValue');
            const zoomValue = document.getElementById('zoomValue');
            const satelliteButton = document.getElementById('satelliteButton');
            const streetButton = document.getElementById('streetButton');
            const topButton = document.getElementById('topButton');
            const obliqueButton = document.getElementById('obliqueButton');
            const routeButton = document.getElementById('routeButton');
            const coordinateBanner = document.getElementById('coordinateBanner');
            const coordinateText = document.getElementById('coordinateText');
            function setActivePreset(button) {
              [topButton, obliqueButton, routeButton].forEach(item => item.classList.toggle('active', item === button));
            }
            function syncCameraUI() {
              bearingSlider.value = Math.round(map.getBearing());
              pitchSlider.value = Math.round(map.getPitch());
              zoomSlider.value = map.getZoom().toFixed(1);
              bearingValue.textContent = `${Math.round(map.getBearing())}°`;
              pitchValue.textContent = `${Math.round(map.getPitch())}°`;
              zoomValue.textContent = `${map.getZoom().toFixed(1)}×`;
            }
            function setBaseLayer(layer) {
              const satellite = layer === 'satellite';
              map.setLayoutProperty('osm', 'visibility', satellite ? 'none' : 'visible');
              map.setLayoutProperty('satellite', 'visibility', satellite ? 'visible' : 'none');
              streetButton.classList.toggle('active', !satellite);
              satelliteButton.classList.toggle('active', satellite);
            }
            satelliteButton.addEventListener('click', () => setBaseLayer('satellite'));
            streetButton.addEventListener('click', () => setBaseLayer('osm'));
            topButton.addEventListener('click', () => {
              setActivePreset(topButton);
              map.easeTo({ pitch: 0, bearing: 0, duration: 650 });
            });
            obliqueButton.addEventListener('click', () => {
              setActivePreset(obliqueButton);
              map.easeTo({ pitch: 52, bearing: -24, duration: 650 });
            });
            routeButton.addEventListener('click', () => {
              setActivePreset(routeButton);
              map.easeTo({ pitch: 62, bearing: routeBearing(), zoom: Math.max(map.getZoom(), 16.5), duration: 650 });
            });
            bearingSlider.addEventListener('input', event => {
              setActivePreset(null);
              map.setBearing(Number(event.target.value));
              syncCameraUI();
            });
            pitchSlider.addEventListener('input', event => {
              setActivePreset(null);
              map.setPitch(Number(event.target.value));
              syncCameraUI();
            });
            zoomSlider.addEventListener('input', event => {
              setActivePreset(null);
              map.setZoom(Number(event.target.value));
              syncCameraUI();
            });
            map.on('move', syncCameraUI);

            window.updateCurrentLocation = function(latitude, longitude) {
              const point = [longitude, latitude];
              const source = map.getSource('current-location');
              const feature = { type: 'Feature', geometry: { type: 'Point', coordinates: point }, properties: {} };
              if (source) {
                source.setData(feature);
              }
              map.panTo(point, { duration: 250 });
            };
            function updateCoordinateBanner(pointLike) {
              const nearest = nearestRoutePoint(pointLike.point);
              if (!nearest || nearest.distance > 58) {
                coordinateBanner.classList.remove('visible');
                map.getCanvas().style.cursor = '';
                return;
              }
              const lngLat = nearest.lngLat;
              const elevation = terrainText(lngLat);
              coordinateText.textContent = `위도 ${lngLat[1].toFixed(7)}  경도 ${lngLat[0].toFixed(7)}  ${elevation}`;
              coordinateBanner.classList.add('visible');
              map.getCanvas().style.cursor = 'crosshair';
            }
            map.on('mousemove', updateCoordinateBanner);
            map.on('touchmove', event => {
              if (event.points && event.points[0]) updateCoordinateBanner({ point: event.points[0] });
            });
            map.on('mouseout', () => {
              coordinateBanner.classList.remove('visible');
              map.getCanvas().style.cursor = '';
            });

            map.on('load', () => {
              map.addSource('route-base', {
                type: 'geojson',
                data: { type: 'Feature', geometry: { type: 'LineString', coordinates: routeLngLat }, properties: {} }
              });
              map.addLayer({
                id: 'route-base',
                type: 'line',
                source: 'route-base',
                paint: {
                  'line-color': '#5f7772',
                  'line-width': 4,
                  'line-opacity': .5
                }
              });
              map.addLayer({
                id: 'route-hover-hit-area',
                type: 'line',
                source: 'route-base',
                paint: {
                  'line-color': '#ffffff',
                  'line-width': 42,
                  'line-opacity': .01
                },
                layout: {
                  'line-cap': 'round',
                  'line-join': 'round'
                }
              });
              map.addSource('score-segments', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: scoreFeatures }
              });
              map.addLayer({
                id: 'score-segments',
                type: 'line',
                source: 'score-segments',
                paint: {
                  'line-color': ['get', 'color'],
                  'line-width': ['get', 'width'],
                  'line-opacity': ['get', 'opacity']
                },
                layout: {
                  'line-cap': 'round',
                  'line-join': 'round'
                }
              });
              map.addSource('accuracy-rings', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: accuracyFeatures }
              });
              map.addLayer({
                id: 'accuracy-rings',
                type: 'line',
                source: 'accuracy-rings',
                paint: {
                  'line-color': '#ff6b66',
                  'line-width': 1,
                  'line-dasharray': [2, 2],
                  'line-opacity': .64
                }
              });
              map.addSource('events', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: eventFeatures }
              });
              map.addLayer({
                id: 'events',
                type: 'circle',
                source: 'events',
                paint: {
                  'circle-radius': 8,
                  'circle-color': ['get', 'color'],
                  'circle-opacity': .96,
                  'circle-stroke-color': '#f4f7f6',
                  'circle-stroke-width': 2
                }
              });
              map.addSource('endpoints', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: endpointFeatures }
              });
              map.addLayer({
                id: 'endpoints',
                type: 'circle',
                source: 'endpoints',
                paint: {
                  'circle-radius': 6,
                  'circle-color': '#071716',
                  'circle-opacity': 1,
                  'circle-stroke-color': ['get', 'color'],
                  'circle-stroke-width': 2
                }
              });
              map.addSource('current-location', {
                type: 'geojson',
                data: { type: 'FeatureCollection', features: [] }
              });
              map.addLayer({
                id: 'current-location-halo',
                type: 'circle',
                source: 'current-location',
                paint: {
                  'circle-radius': 15,
                  'circle-color': 'rgba(0, 122, 255, .18)'
                }
              });
              map.addLayer({
                id: 'current-location',
                type: 'circle',
                source: 'current-location',
                paint: {
                  'circle-radius': 8,
                  'circle-color': '#007aff',
                  'circle-stroke-color': 'rgba(255,255,255,.86)',
                  'circle-stroke-width': 3
                }
              });

              map.on('click', 'events', event => {
                const feature = event.features && event.features[0];
                if (!feature) return;
                const props = feature.properties || {};
                new maplibregl.Popup({ offset: 12, maxWidth: '260px' })
                  .setLngLat(feature.geometry.coordinates)
                  .setHTML(`<div class="map-popup"><strong>${props.decision}</strong><small>${props.time} · ${props.label} · 상대 노면 점수 ${props.score}점</small></div>`)
                  .addTo(map);
              });
              map.on('mouseenter', 'events', () => { map.getCanvas().style.cursor = 'pointer'; });
              map.on('mouseleave', 'events', () => { map.getCanvas().style.cursor = ''; });

              if (routeLngLat.length > 1) {
                const bounds = routeLngLat.reduce((current, point) => current.extend(point), new maplibregl.LngLatBounds(routeLngLat[0], routeLngLat[0]));
                map.fitBounds(bounds, { padding: 42, maxZoom: 16.7, pitch: 52, bearing: -24, duration: 0 });
              }
              if (data.currentLocation) {
                window.updateCurrentLocation(data.currentLocation[0], data.currentLocation[1]);
              }
              syncCameraUI();
            });
          </script>
        </body>
        </html>
        """
    }

    private func updateCurrentLocation(_ coordinate: Coordinate) {
        pendingCoordinate = coordinate
        guard didLoadPage else { return }
        let script = String(format: "window.updateCurrentLocation(%.8f, %.8f);", coordinate.latitude, coordinate.longitude)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private static func loadBundledScorePoints() -> [ScorePoint] {
        guard let data = try? DemoResourceBundle.data(named: "sensor-2026-08-09-route-scores.csv"),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return csvRows(text).compactMap { row in
            guard
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? "")
            else { return nil }
            let eligibleText = (row["eligible"] ?? "").lowercased()
            return ScorePoint(
                time: Double(row["seconds_elapsed"] ?? "") ?? 0,
                latitude: latitude,
                longitude: longitude,
                score: Double(row["score"] ?? "") ?? 0,
                eligible: eligibleText == "true" || eligibleText == "1"
            )
        }
    }

    private static func loadBundledEvents() -> [EventPoint] {
        guard let data = try? DemoResourceBundle.data(named: "sensor-2026-08-09-events.csv"),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return csvRows(text).compactMap { row in
            guard
                let id = row["id"],
                let latitude = Double(row["latitude"] ?? ""),
                let longitude = Double(row["longitude"] ?? "")
            else { return nil }
            let visualStatus = row["visualStatus"] ?? ""
            return EventPoint(
                id: id,
                time: Double(row["time"] ?? "") ?? 0,
                latitude: latitude,
                longitude: longitude,
                accuracy: Double(row["accuracy"] ?? "") ?? 14,
                score: Double(row["score"] ?? "") ?? 0,
                evidence: (visualStatus == "video-linked" || visualStatus == "supported") ? "video" : "sensor",
                decision: row["decision"] ?? "상대적 고진동 구간"
            )
        }
    }

    private static func csvRows(_ text: String) -> [[String: String]] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first else { return [] }
        let headers = splitCSVLine(headerLine)
        return lines.dropFirst().map { line in
            let values = splitCSVLine(line)
            return Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                (header, index < values.count ? values[index] : "")
            })
        }
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var insideQuotes = false
        for character in line {
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == "," && !insideQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        values.append(current)
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static func displayName(for route: Route) -> String {
        switch route.providerOption {
        case "pm": return "최소시간"
        case "pm_main_road": return "큰길 위주"
        case "pm_short_distance_priority": return "최단거리"
        case "sensor_logger": return "센서 주행"
        default: return "선택 경로"
        }
    }
}

extension R2DOSMRideMapViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoadPage = true
        if let pendingCoordinate {
            updateCurrentLocation(pendingCoordinate)
        }
    }
}
#endif

import SwiftUI
import R2DCore

@MainActor
public final class RideViewModel: ObservableObject {
    @Published public private(set) var state: ActiveRideState
    @Published public var summary: RideSummary?
    public let coordinator: ActiveRideCoordinator
    public let mapRenderer: IMapRenderer
    public let featureFlags: FeatureFlags
    public let demoReplayController: DemoReplayControlling?
    private var unsubscribe: Unsubscribe?
    private var isAutoFinishing = false
    public init(coordinator: ActiveRideCoordinator, mapRenderer: IMapRenderer = NoopMapRenderer(), featureFlags: FeatureFlags = .production, demoReplayController: DemoReplayControlling? = nil) {
        self.coordinator = coordinator; self.mapRenderer = mapRenderer; self.featureFlags = featureFlags; self.demoReplayController = demoReplayController; state = coordinator.getSnapshot()
        unsubscribe = coordinator.subscribe { [weak self] in self?.accept($0) }
    }
    public func bootstrap() { Task { try? await coordinator.searchRoutes(origin: .init(latitude: 37.5452, longitude: 127.0392), destination: .init(latitude: 37.5534, longitude: 127.0488)); await coordinator.syncRiskViewport(.init(minLatitude: 37.53, minLongitude: 127.02, maxLatitude: 37.58, maxLongitude: 127.09), zoomLevel: 14) } }
    public func startSelectedRoute() { _ = try? coordinator.prepare(); _ = try? coordinator.start() }
    public func finishRide() { Task { summary = try? await coordinator.finish(); isAutoFinishing = false } }
    private func accept(_ value: ActiveRideState) {
        state = value
        guard featureFlags.replayLocationEnabled, !isAutoFinishing, value.session?.state == .active, value.navigationProgress?.progressRatio ?? 0 >= 0.995 else { return }
        isAutoFinishing = true; finishRide()
    }
}

public struct R2DAppView: View {
    @StateObject private var model: RideViewModel
    public init(model: RideViewModel) { _model = StateObject(wrappedValue: model) }
    public var body: some View {
        ZStack {
            if model.state.session?.state == .active || model.state.session?.state == .paused {
                ActiveRideShell(model: model)
            } else if let summary = model.summary { RideResultView(summary: summary, telemetry: model.state.telemetrySummary, flags: model.featureFlags) }
            else { NavigatorHomeView(model: model) }
        }.task { model.bootstrap() }.preferredColorScheme(.dark)
    }
}

private struct NavigatorHomeView: View {
    @ObservedObject var model: RideViewModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack { VStack(alignment: .leading) { Text("R2D NAVIGATOR").font(.caption).foregroundStyle(.mint); Text("어디로 달릴까요?").font(.largeTitle.bold()); Text("주행하며 도로 정보를 수집하고, 검증된 위험 구간을 안내합니다.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "location.fill").font(.title).foregroundStyle(.mint) }
                    if model.featureFlags.replayLocationEnabled { Label("데모 모드 · 로컬 데이터", systemImage: "play.circle.fill").font(.caption.bold()).padding(8).background(.mint.opacity(0.16), in: Capsule()).frame(maxWidth: .infinity, alignment: .leading) }
                    RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [.teal.opacity(0.35), .blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 210).overlay { VStack(spacing: 8) { Image(systemName: "map.fill").font(.system(size: 52)); Text("현재 위치 · 서울숲"); Text("위험 정보 · 로컬 스냅샷 최신").font(.caption).foregroundStyle(.secondary); HStack { Label("정보 부족", systemImage: "circle.fill").foregroundStyle(.gray); Label("주의", systemImage: "circle.fill").foregroundStyle(.orange); Label("높은 위험", systemImage: "circle.fill").foregroundStyle(.red) }.font(.caption2) } }
                    HStack { Image(systemName: "magnifyingglass"); Text("R2D Navigator Demo Route · 한강공원") }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    ReadinessCard(model: model)
                    ForEach(model.state.routes) { route in
                        Button { model.coordinator.selectRoute(route) } label: {
                            HStack { VStack(alignment: .leading, spacing: 4) { Text(routeTitle(route.id)).font(.headline); Text(routeDescription(route.id)).font(.caption).foregroundStyle(.secondary); Text(String(format: "%.1f km · 약 %d분", route.totalDistance / 1000, max(1, Int(route.totalDuration) / 60))).font(.caption2).foregroundStyle(.mint) }; Spacer(); Image(systemName: model.state.selectedRoute?.id == route.id ? "checkmark.circle.fill" : "circle").foregroundStyle(.mint) }.padding().background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    Button("데모 경로 시작") { model.startSelectedRoute() }.buttonStyle(PrimaryButton()).disabled(model.state.selectedRoute == nil)
                }.padding()
            }.background(Color(red: 0.035, green: 0.07, blue: 0.09)).navigationTitle("R2D")
        }
    }
    private func routeTitle(_ id: String) -> String { if id.contains("safe") { return "안전 경로" }; if id.contains("bike") { return "자전거 우선" }; return "빠른 경로" }
    private func routeDescription(_ id: String) -> String { if id.contains("safe") { return "위험 확정 구간 최소 · 약 1분 우회" }; if id.contains("bike") { return "자전거도로 비율 78% · 주의 구간 1개" }; return "가장 짧은 시간 · 정보 부족 구간 18%" }
}

private struct ReadinessCard: View {
    @ObservedObject var model: RideViewModel
    var body: some View { VStack(alignment: .leading, spacing: 10) {
        HStack { Text("주행 준비 상태").font(.headline); Spacer(); if model.featureFlags.replayLocationEnabled { Text("데모 데이터").font(.caption.bold()).foregroundStyle(.mint) } }
        StatusRow(name: "위치", ready: model.state.locationReadiness.canStart, detail: model.featureFlags.replayLocationEnabled ? "데모 위치 사용" : "준비 완료")
        StatusRow(name: "센서", ready: model.state.sensorReadiness.canStart, detail: model.featureFlags.replayLocationEnabled ? "데모 센서 사용" : "준비 완료")
        StatusRow(name: "지도", ready: true, detail: "준비 완료")
        StatusRow(name: "위험 레이어", ready: true, detail: "준비 완료")
        StatusRow(name: "경로", ready: model.state.selectedRoute != nil, detail: model.state.selectedRoute == nil ? "안전 경로를 선택하세요" : "준비 완료")
        StatusRow(name: "데이터 모드", ready: true, detail: model.featureFlags.replayLocationEnabled ? "Demo Replay" : "Live")
        if model.state.locationReadiness.authorization == .notDetermined { Button("위치 권한 요청") { model.coordinator.requestLocationAuthorization() } }
        if !model.state.locationReadiness.canStart || !model.state.sensorReadiness.canStart { Text("제한 모드: 일부 주행 데이터가 수집되지 않을 수 있습니다.").font(.caption).foregroundStyle(.orange) }
    }.padding().background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16)) }
}
private struct StatusRow: View { let name: String, ready: Bool, detail: String; var body: some View { HStack { Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ready ? .mint : .orange); Text(name); Spacer(); Text(detail).font(.caption).foregroundStyle(.secondary) } } }

private struct ActiveRideShell: View {
    @ObservedObject var model: RideViewModel
    var body: some View {
        ZStack(alignment: .top) {
            if model.state.activeView == .navigator { NavigatorRideView(model: model) } else { GameRideView(model: model) }
            SafetyOverlay(state: model.state)
        }
    }
}

private struct NavigatorRideView: View {
    @ObservedObject var model: RideViewModel
    var body: some View {
        ZStack {
            mapSurface.ignoresSafeArea()
            VStack { HStack { Button { model.coordinator.showFullRoute() } label: { Image(systemName: "map") }; Button { model.coordinator.focusNextTurn() } label: { Image(systemName: "arrow.turn.up.right") }; Spacer(); Label(model.featureFlags.replayLocationEnabled ? "DEMO" : "LIVE", systemImage: "location.fill").font(.caption.bold()).padding(8).background(.ultraThinMaterial, in: Capsule()) }.buttonStyle(.borderedProminent); if model.featureFlags.demoControlsEnabled, let controller = model.demoReplayController { DemoControlPanel(controller: controller, model: model) }; Spacer(); VStack(spacing: 8) { Text(model.state.isRerouting ? "경로를 다시 찾는 중" : (model.state.nextInstruction?.title ?? "경로를 확인하는 중")).font(.title2.bold()); Text(String(format: "다음 안내 %.0f m · 남은 거리 %.0f m", model.state.nextInstruction?.distanceM ?? 0, model.state.navigationProgress?.remainingDistance ?? model.state.selectedRoute?.remainingDistance ?? 0)); ProgressView(value: model.state.navigationProgress?.progressRatio ?? 0).tint(.mint); Text(String(format: "ETA %d분 · GPS 정상 · 위험 정보 최신", Int(model.state.navigationProgress?.remainingDuration ?? 0) / 60)).font(.caption).foregroundStyle(.secondary) }.padding().frame(maxWidth: .infinity).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)); RideControls(model: model) }.padding()
        }
    }
    @ViewBuilder private var mapSurface: some View {
        if let renderer = model.mapRenderer as? AppleMapKitRenderer { AppleMapKitRendererView(renderer: renderer) }
        else { MapSDKView(state: model.state.mapState) }
    }
}

private struct GameRideView: View {
    @ObservedObject var model: RideViewModel
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.48), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 18) { Text("GAME · 자동 전투 미리보기").font(.caption.bold()).foregroundStyle(.mint); Spacer(); Image(systemName: "shield.lefthalf.filled.badge.checkmark").font(.system(size: 86)).symbolEffect(.pulse); Text("한강 수호자와 자동 전투 중").font(.title.bold())
                if let game = model.state.game {
                    ProgressView(value: Double(game.remainingHp), total: Double(game.maxHp)).tint(.pink)
                    Text("HP \(game.remainingHp) / \(game.maxHp)")
                    HStack { Stat(label: "예상 피해", value: game.estimatedTotalDamage, pending: true); Stat(label: "확정 피해", value: game.confirmedTotalDamage, pending: false) }
                    Text(game.processingState == .awaitingServer ? "서버 확인 대기 중" : "서버 확정").font(.caption).foregroundStyle(.secondary)
                }
                if let instruction = model.state.nextInstruction { VStack(alignment: .leading, spacing: 5) { Label("Navigator 미니 안내", systemImage: "map.fill").font(.headline); Text("\(Int(instruction.distanceM))m 후 · \(instruction.title)"); Text(String(format: "남은 거리 %.0f m", model.state.navigationProgress?.remainingDistance ?? 0)).font(.caption).foregroundStyle(.secondary) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)) }
                Button { model.coordinator.switchView(.navigator) } label: { Label("Navigator로 복귀", systemImage: "map.fill") }.buttonStyle(PrimaryButton())
                Spacer(); RideControls(model: model)
            }.padding()
        }
    }
}

private struct Stat: View { let label: String; let value: Int; let pending: Bool; var body: some View { VStack { Text(label).font(.caption); Text("\(value)").font(.title.bold()); if pending { Text("PENDING").font(.caption2).foregroundStyle(.orange) } }.frame(maxWidth: .infinity).padding().background(.white.opacity(pending ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 16)) } }

private struct RideControls: View {
    @ObservedObject var model: RideViewModel
    var body: some View { VStack(spacing: 10) { HStack(spacing: 14) { Label("GPS", systemImage: model.state.locationReadiness.canStart ? "location.fill" : "location.slash"); Label("Sensor", systemImage: model.state.sensorReadiness.canStart ? "waveform" : "waveform.slash"); Label("Queue \(model.state.queuedChunkCount)", systemImage: "arrow.up.circle") }.font(.caption).foregroundStyle(.secondary); HStack {
        if model.featureFlags.gameEnabled { Button { model.coordinator.switchView(model.state.activeView == .navigator ? .game : .navigator) } label: { Label(model.state.activeView == .navigator ? "Game 미리보기" : "Navigator", systemImage: model.state.activeView == .navigator ? "gamecontroller.fill" : "map.fill") } }
        Spacer(); Button(model.state.session?.state == .paused ? "재개" : "일시정지") { if model.state.session?.state == .paused { try? model.coordinator.resume() } else { try? model.coordinator.pause() } }
        Spacer(); Button("종료") { model.finishRide() }.foregroundStyle(.red)
    } }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22)) }
}

private struct SafetyOverlay: View {
    let state: ActiveRideState
    var body: some View { VStack(spacing: 8) {
        if let warning = state.roadWarning { Label("\(warningMessage(warning.messageKey)) · \(Int(warning.distanceM))m", systemImage: "exclamationmark.triangle.fill").padding().frame(maxWidth: .infinity).background(warning.severity == .high ? .red : .orange) }
        else if state.activeView == .game, let instruction = state.nextInstruction { Label("\(Int(instruction.distanceM))m · \(instruction.title)", systemImage: "arrow.turn.up.right").padding(10).background(.ultraThinMaterial, in: Capsule()) }
        else if state.isRerouting { Label("경로를 다시 찾는 중", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").padding(10).background(.orange, in: Capsule()) }
    }.padding(.top, 8).padding(.horizontal) }
    private func warningMessage(_ key: String) -> String { switch key { case "road.confirmed_damage": "전방 도로 파손"; case "road.restricted": "전방 통행 제한"; case "road.rough": "전방 거친 노면"; case "road.suspected_damage": "전방 노면 주의"; default: "전방 도로 위험" } }
}

private struct DemoControlPanel: View { let controller: DemoReplayControlling; @ObservedObject var model: RideViewModel; var body: some View { VStack(spacing: 7) { HStack { Text("DEMO CONTROL").font(.caption.bold()); Spacer(); ForEach([1.0, 3.0, 5.0], id: \.self) { speed in Button("\(Int(speed))x") { controller.setPlaybackSpeed(speed) }.buttonStyle(.bordered).tint(controller.playbackSpeed == speed ? .mint : .gray) } }; HStack { Button("처음") { controller.restart() }; Button("위험") { controller.seek(to: .risk) }; Button("Reroute") { controller.seek(to: .reroute) }; Button("도착 전") { controller.seek(to: .destination) } }.font(.caption).buttonStyle(.bordered) }.padding(10).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14)) } }

private struct RideResultView: View { let summary: RideSummary; let telemetry: TelemetryQueueSummary; let flags: FeatureFlags; var body: some View { VStack(spacing: 20) { Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(.mint); Text("주행 완료").font(.largeTitle.bold()); Text(String(format: "유효 거리 %.0f m", summary.validDistanceM)); Text("확정 피해 \(summary.confirmedBaseDamage + summary.confirmedDataDamage)"); if flags.rewardEnabled { Text("보상 대기 \(summary.pendingReward) · 확정 \(summary.confirmedReward)") }; Text(summary.isFinal ? "서버 확정 결과" : "로컬 데모 결과").foregroundStyle(.secondary); Text("안전한 주행이 완료되었습니다.").font(.headline) }.padding() } }

private struct PrimaryButton: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline).frame(maxWidth: .infinity).padding().background(.mint.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.black) } }

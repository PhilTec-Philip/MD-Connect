import SwiftUI

/// Livemap: live positions of on-duty colleagues ("UserMarker"), marker markers
/// (zones/shapes) and active dispatches. Offers list, map and units views like
/// the FiveNet web client.
///
/// The map renders the same San Andreas tiles as the FiveNet web app
/// (`/images/livemap/tiles/{postal|satellite}/{z}/{x}/{y}.webp`) using the
/// custom CRS from `app/composables/livemap/useMapProjection.ts`.
///
/// Dedicated route type so the marker links resolve against a destination
/// registered on this module root only. Sharing `CentrumRoute` with the
/// `CentrumView` module root registered two `navigationDestination`s for the
/// same type in one stack (white screen / double push).
enum LiveMapRoute: Hashable {
    case unit(Int64)
    case dispatch(Int64)
}

struct LiveMapView: View {
    @Environment(AppState.self) private var appState

    private enum ViewMode: String, CaseIterable, Identifiable {
        case duty = "Meine Einheit"
        case map = "Karte"
        case units = "Einheiten"

        var id: String { rawValue }
    }

    private enum MapTileLayer: String, CaseIterable, Identifiable {
        case postal = "postal"
        case satellite = "satellite"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .postal: "Postleitzahl"
            case .satellite: "Satellit"
            }
        }

        var backgroundColor: Color {
            Color(hex: rawValue == "postal" ? "74aace" : "133e6b") ?? .blue
        }
    }

    @State private var viewMode: ViewMode = .map
    @AppStorage("livemapTileLayer") private var tileLayer: MapTileLayer = .postal
    @AppStorage("livemapMapZoom") private var mapZoom = MapProjection.minZoom
    @State private var startZoom = MapProjection.minZoom
    @State private var mapCenter = CGPoint(x: 2000, y: 2000)
    @State private var hasLoadedInitialCenter = false
    @State private var dragStart: (center: CGPoint, zoom: Int)?
    @AppStorage("livemapShowGrid") private var showGrid = false
    @AppStorage("livemapShowMarkerMarkers") private var showMarkerMarkers = true
    @AppStorage("livemapShowMarkerLabels") private var showMarkerLabels = true
    @State private var selectedMarker: Resources_Livemap_Markers_MarkerMarker?
    @AppStorage("livemapShowHeatmap") private var showHeatmap = false
    @State private var heatmapEntries: [Resources_Livemap_Heatmap_HeatmapEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, Theme.Spacing.md)

            Group {
                switch viewMode {
                case .duty:
                    MyDutyView()
                case .map:
                    tileMap
                case .units:
                    unitsTab
                }
            }
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .pendingAlarmBell()
        .moduleNavTitle(.livemap, title: viewMode == .duty ? "Meine Einheit" : nil)
        .navConnectionDot()
        .navigationDestination(for: LiveMapRoute.self) { route in
            switch route {
            case .unit(let id):
                UnitDetailView(unitID: id)
            case .dispatch(let id):
                DispatchDetailView(dispatchID: id)
            }
        }
        .sheet(item: $selectedMarker) { marker in
            MarkerMarkerDetailSheet(marker: marker)
        }
        .task {
            await loadInitialCenterIfNeeded()
            await appState.startCentrumStream()
            await appState.startLivemapStream()
            if showHeatmap {
                await loadHeatmap()
            }
            var centrumTicks = 0
            while !Task.isCancelled {
                await appState.loadCentrum()
                // Low-frequency heatmap refresh: every 60 cycles (= 30 min)
                // plus the manual triggers (toggle on / initial load).
                centrumTicks += 1
                if showHeatmap && centrumTicks >= 60 {
                    centrumTicks = 0
                    await loadHeatmap()
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: showHeatmap) { _, isOn in
            if isOn {
                Task { await loadHeatmap() }
            } else {
                heatmapEntries = []
            }
        }
        .onDisappear {
            heatmapEntries = []
        }
        .alert("Livemap-Fehler", isPresented: Binding(
            get: { appState.livemapError != nil },
            set: { if !$0 { appState.clearLivemapError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.livemapError ?? "")
        }
    }

    // MARK: - Map view (San Andreas tiles)

    private var tileMap: some View {
        GeometryReader { proxy in
            let centerPixel = MapProjection.project(mapCenter, zoom: mapZoom)
            let viewportOrigin = CGPoint(
                x: centerPixel.x - proxy.size.width / 2,
                y: centerPixel.y - proxy.size.height / 2
            )
            let minTileX = Int(floor(viewportOrigin.x / MapProjection.tileSize))
            let maxTileX = Int(floor((viewportOrigin.x + proxy.size.width) / MapProjection.tileSize))
            let minTileY = Int(floor(viewportOrigin.y / MapProjection.tileSize))
            let maxTileY = Int(floor((viewportOrigin.y + proxy.size.height) / MapProjection.tileSize))

            ZStack {
                tileLayer.backgroundColor
                    .ignoresSafeArea()

                ForEach(minTileX...maxTileX, id: \.self) { tx in
                    ForEach(minTileY...maxTileY, id: \.self) { ty in
                        MapTileView(
                            url: tileURL(z: mapZoom, x: tx, y: ty),
                            backgroundColor: tileLayer.backgroundColor
                        )
                        .frame(width: MapProjection.tileSize, height: MapProjection.tileSize)
                        .position(
                            x: CGFloat(tx) * MapProjection.tileSize - viewportOrigin.x + MapProjection.tileSize / 2,
                            y: CGFloat(ty) * MapProjection.tileSize - viewportOrigin.y + MapProjection.tileSize / 2
                        )
                    }
                }

                if showGrid {
                    gridLayer(in: proxy.size, viewportOrigin: viewportOrigin)
                }

                if showHeatmap {
                    heatmapLayer(in: proxy.size, viewportOrigin: viewportOrigin)
                }

                if showMarkerMarkers {
                    markerMarkersLayer(in: proxy.size, viewportOrigin: viewportOrigin)
                }

                markerLayer(in: proxy.size, viewportOrigin: viewportOrigin)

                if appState.livemapMarkers.isEmpty && positionedDispatches.isEmpty && appState.livemapMarkerMarkers.isEmpty {
                    ContentUnavailableView(
                        "Keine Positionen",
                        systemImage: "map",
                        description: Text("Es sind gerade keine Kollegen oder Einsätze auf der Karte sichtbar.")
                    )
                }

                mapMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding()

                zoomControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding()
            }
            .animation(.easeOut(duration: 0.2), value: mapZoom)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var mapMenu: some View {
        Menu {
            Picker("Kartenstil", selection: $tileLayer) {
                ForEach(MapTileLayer.allCases) { layer in
                    Text(layer.label).tag(layer)
                }
            }

            Toggle("Marker anzeigen", isOn: $showMarkerMarkers)
            Toggle("Markerbezeichnungen anzeigen", isOn: $showMarkerLabels)
                .disabled(!showMarkerMarkers)
            Toggle("Raster anzeigen", isOn: $showGrid)
            Toggle("Einsatz-Heatmap", isOn: $showHeatmap)

            Button {
                resetMap()
            } label: {
                Label("Karte zurücksetzen", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func resetMap() {
        mapZoom = MapProjection.minZoom
        startZoom = MapProjection.minZoom
        mapCenter = CGPoint(x: 2000, y: 2000)
    }

    private func tileURL(z: Int, x: Int, y: Int) -> URL {
        let base = appState.client?.baseURL
        return (base ?? URL(string: "https://localhost")!)
            .appendingPathComponent("images/livemap/tiles/\(tileLayer.rawValue)/\(z)/\(x)/\(y).webp")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (mapCenter, mapZoom)
                }
                guard let start = dragStart else { return }
                let startPixel = MapProjection.project(start.center, zoom: start.zoom)
                let currentPixel = CGPoint(
                    x: startPixel.x - value.translation.width,
                    y: startPixel.y - value.translation.height
                )
                mapCenter = clampCenter(MapProjection.unproject(currentPixel, zoom: mapZoom))
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let target = startZoom + Int(log2(value).rounded())
                mapZoom = min(max(target, MapProjection.minZoom), MapProjection.maxZoom)
            }
            .onEnded { _ in
                startZoom = mapZoom
            }
    }

    private func zoomBy(_ delta: Int) {
        startZoom = mapZoom
        let target = mapZoom + delta
        mapZoom = min(max(target, MapProjection.minZoom), MapProjection.maxZoom)
    }

    private var zoomControls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                zoomBy(1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(mapZoom >= MapProjection.maxZoom)

            Button {
                zoomBy(-1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(mapZoom <= MapProjection.minZoom)
        }
    }

    private func clampCenter(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, -4000), 8000),
            y: min(max(point.y, -4000), 8000)
        )
    }

    /// Centers the map on Los Santos (postal 7135) once, so the initial view
    /// is not the bare tile origin (2000/2000).
    private func loadInitialCenterIfNeeded() async {
        guard !hasLoadedInitialCenter else { return }
        hasLoadedInitialCenter = true
        guard let baseURL = appState.client?.baseURL,
              let postal = await PostalLoader.shared.location(for: "7135", baseURL: baseURL) else { return }
        mapCenter = clampCenter(CGPoint(x: postal.x, y: postal.y))
    }

    // MARK: - Map overlays

    /// Projects a game-space point into view coordinates.
    private func toView(_ point: CGPoint, viewportOrigin: CGPoint) -> CGPoint {
        let p = MapProjection.project(point, zoom: mapZoom)
        return CGPoint(x: p.x - viewportOrigin.x, y: p.y - viewportOrigin.y)
    }

    /// Game units to screen pixels at the current zoom level.
    private var unitsToPixels: Double {
        MapProjection.scaleX * pow(2, Double(mapZoom))
    }

    private func markerLayer(in size: CGSize, viewportOrigin: CGPoint) -> some View {
        ZStack {
            ForEach(positionedDispatches) { dispatch in
                let p = toView(CGPoint(x: dispatch.x, y: dispatch.y), viewportOrigin: viewportOrigin)
                dispatchMarkerView(dispatch)
                    .position(x: p.x, y: p.y)
            }

            ForEach(appState.livemapMarkers) { marker in
                let p = toView(CGPoint(x: marker.x, y: marker.y), viewportOrigin: viewportOrigin)
                userMarkerView(marker)
                    .position(x: p.x, y: p.y)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Dispatches that carry map coordinates (x/y != 0).
    private var positionedDispatches: [Resources_Centrum_Dispatches_Dispatch] {
        appState.dispatches.filter { $0.x != 0 || $0.y != 0 }
    }

    // MARK: Marker markers (zones / shapes)

    private func markerMarkersLayer(in size: CGSize, viewportOrigin: CGPoint) -> some View {
        ZStack {
            ForEach(appState.livemapMarkerMarkers) { marker in
                markerMarkerShape(marker, viewportOrigin: viewportOrigin)
            }
            if showMarkerLabels {
                ForEach(appState.livemapMarkerMarkers) { marker in
                    markerMarkerLabel(marker, viewportOrigin: viewportOrigin)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Draws the marker shape with a precise hit area. The tap target is the
    /// shape itself; labels are drawn separately so they cannot swallow taps.
    @ViewBuilder
    private func markerMarkerShape(_ marker: Resources_Livemap_Markers_MarkerMarker, viewportOrigin: CGPoint) -> some View {
        let color = markerMarkerColor(marker)
        let origin = CGPoint(x: marker.x, y: marker.y)
        let anchor = toView(origin, viewportOrigin: viewportOrigin)

        switch marker.type {
        case .dot:
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .stroke(.black, lineWidth: 1.5)
                }
                .contentShape(Circle())
                .onTapGesture { selectedMarker = marker }
                .position(x: anchor.x, y: anchor.y)
        case .circle:
            if marker.hasData {
                let radius = max(4, CGFloat(marker.data.circle.radius) * unitsToPixels)
                Circle()
                    .fill(color.opacity(markerFillOpacity(marker)))
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: radius * 2, height: radius * 2)
                    .contentShape(Circle())
                    .onTapGesture { selectedMarker = marker }
                    .position(x: anchor.x, y: anchor.y)
            }
        case .icon:
            iconMarker(marker, color: color, anchor: anchor)
        case .rectangle:
            if marker.hasData {
                let end = toView(CGPoint(x: marker.data.rectangle.endX, y: marker.data.rectangle.endY), viewportOrigin: viewportOrigin)
                let width = abs(end.x - anchor.x)
                let height = abs(end.y - anchor.y)
                let center = CGPoint(x: min(anchor.x, end.x) + width / 2, y: min(anchor.y, end.y) + height / 2)
                Rectangle()
                    .fill(color.opacity(markerFillOpacity(marker)))
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedMarker = marker }
                    .position(x: center.x, y: center.y)
            }
        case .polygon, .polyline:
            let points = shapePoints(marker).map { toView($0, viewportOrigin: viewportOrigin) }
            if points.count >= 2 {
                let shape = path(for: points, closed: marker.type == .polygon)
                shape
                    .fill(marker.type == .polygon ? color.opacity(markerFillOpacity(marker)) : Color.clear)
                    .stroke(color, lineWidth: 2)
                    .contentShape(shape)
                    .onTapGesture { selectedMarker = marker }
            }
        case .unspecified, .UNRECOGNIZED:
            EmptyView()
        }
    }

    /// The name label of a marker marker, placed in view coordinates.
    @ViewBuilder
    private func markerMarkerLabel(_ marker: Resources_Livemap_Markers_MarkerMarker, viewportOrigin: CGPoint) -> some View {
        if !marker.name.isEmpty {
            switch marker.type {
            case .dot, .icon:
                EmptyView()
            case .circle, .rectangle, .polygon, .polyline, .unspecified, .UNRECOGNIZED:
                let point = markerLabelPoint(marker, viewportOrigin: viewportOrigin)
                Text(marker.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(x: point.x, y: point.y)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Where to place a marker marker's name label (view coordinates).
    private func markerLabelPoint(_ marker: Resources_Livemap_Markers_MarkerMarker, viewportOrigin: CGPoint) -> CGPoint {
        let anchor = toView(CGPoint(x: marker.x, y: marker.y), viewportOrigin: viewportOrigin)
        guard marker.hasData, let data = marker.data.data else { return anchor }
        switch data {
        case .rectangle(let rectangle):
            let end = toView(CGPoint(x: rectangle.endX, y: rectangle.endY), viewportOrigin: viewportOrigin)
            return CGPoint(x: (anchor.x + end.x) / 2, y: (anchor.y + end.y) / 2)
        case .polygon(let polygon):
            return centroid(of: polygon.points.map { toView(CGPoint(x: $0.x, y: $0.y), viewportOrigin: viewportOrigin) }, fallback: anchor)
        case .polyline(let polyline):
            return centroid(of: polyline.points.map { toView(CGPoint(x: $0.x, y: $0.y), viewportOrigin: viewportOrigin) }, fallback: anchor)
        case .circle, .icon:
            return anchor
        }
    }

    private func centroid(of points: [CGPoint], fallback: CGPoint) -> CGPoint {
        guard !points.isEmpty else { return fallback }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func markerFillOpacity(_ marker: Resources_Livemap_Markers_MarkerMarker) -> Double {
        guard marker.hasData, let data = marker.data.data else { return 0.15 }
        let raw: Float
        switch data {
        case .circle(let circle): raw = circle.opacity
        case .rectangle(let rectangle): raw = rectangle.opacity
        case .polygon(let polygon): raw = polygon.opacity
        case .icon, .polyline: raw = 0
        }
        let value = raw <= 0 ? 15 : raw
        return Double(value) / 100
    }

    private func iconMarker(_ marker: Resources_Livemap_Markers_MarkerMarker, color: Color, anchor: CGPoint) -> some View {
        VStack(spacing: 1) {
            MapMarkerIconView(icon: markerIconName(marker), color: .white, size: 12)
                .frame(width: 20, height: 20)
                .background(color, in: Circle())
                .shadow(radius: 1)
            if showMarkerLabels && !marker.name.isEmpty {
                Text(marker.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { selectedMarker = marker }
        .position(x: anchor.x, y: anchor.y)
    }

    private func markerIconName(_ marker: Resources_Livemap_Markers_MarkerMarker) -> String {
        guard marker.hasData, let data = marker.data.data, case .icon(let icon) = data else {
            return "mdi:map-marker-question"
        }
        return icon.icon.isEmpty ? "mdi:map-marker-question" : icon.icon
    }

    private func shapePoints(_ marker: Resources_Livemap_Markers_MarkerMarker) -> [CGPoint] {
        var points = [CGPoint(x: marker.x, y: marker.y)]
        guard marker.hasData, let data = marker.data.data else { return points }
        switch data {
        case .polygon(let polygon):
            points.append(contentsOf: polygon.points.map { CGPoint(x: $0.x, y: $0.y) })
        case .polyline(let polyline):
            points.append(contentsOf: polyline.points.map { CGPoint(x: $0.x, y: $0.y) })
        default:
            break
        }
        return points
    }

    private func path(for points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }

    // MARK: Grid

    private func gridLayer(in size: CGSize, viewportOrigin: CGPoint) -> some View {
        let interval = gridInterval(for: mapZoom)
        let lower = CGPoint(x: -4000, y: -4000)
        let upper = CGPoint(x: 8000, y: 8000)
        let minX = floor(lower.x / interval) * interval
        let maxX = ceil(upper.x / interval) * interval
        let minY = floor(lower.y / interval) * interval
        let maxY = ceil(upper.y / interval) * interval

        return Canvas { context, _ in
            var x = minX
            while x <= maxX {
                let start = toView(CGPoint(x: x, y: minY), viewportOrigin: viewportOrigin)
                let end = toView(CGPoint(x: x, y: maxY), viewportOrigin: viewportOrigin)
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .color(.black.opacity(0.35)), lineWidth: 0.5)
                x += interval
            }
            var y = minY
            while y <= maxY {
                let start = toView(CGPoint(x: minX, y: y), viewportOrigin: viewportOrigin)
                let end = toView(CGPoint(x: maxX, y: y), viewportOrigin: viewportOrigin)
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .color(.black.opacity(0.35)), lineWidth: 0.5)
                y += interval
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func gridInterval(for zoom: Int) -> Double {
        switch zoom {
        case 1: return 1000
        case 2...3: return 500
        case 4...5: return 250
        case 6...7: return 100
        default: return 500
        }
    }

    // MARK: Heatmap

    /// Renders the dispatch heatmap as overlapping radial-gradient hotspots.
    /// Each entry is a weighted point (x/y in game space, w = intensity); the
    /// hotspot radius and opacity are normalized against the strongest entry.
    private func heatmapLayer(in size: CGSize, viewportOrigin: CGPoint) -> some View {
        let maxWeight = heatmapEntries.map(\.w).max() ?? 1
        return ZStack {
            ForEach(heatmapEntries.indices, id: \.self) { index in
                let entry = heatmapEntries[index]
                let point = toView(CGPoint(x: entry.x, y: entry.y), viewportOrigin: viewportOrigin)
                let intensity = maxWeight > 0 ? min(max(Double(entry.w) / Double(maxWeight), 0), 1) : 0
                let radius = 12 + 40 * intensity
                let opacity = 0.18 + 0.4 * intensity
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            Color.orange.opacity(opacity),
                            Color.red.opacity(opacity * 0.6),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    ))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: point.x, y: point.y)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func loadHeatmap() async {
        guard let client = appState.client else { return }
        do {
            let response = try await client.getDispatchHeatmap()
            heatmapEntries = response.entries
        } catch {
            heatmapEntries = []
        }
    }

    // MARK: Markers (user / dispatch)

    @ViewBuilder
    private func userMarkerView(_ marker: Resources_Livemap_Markers_UserMarker) -> some View {
        let label = VStack(spacing: 2) {
            Circle()
                .fill(markerColor(marker))
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                }
                .shadow(radius: 2)
            if marker.hasUnit {
                unitMarkerLabel(marker.unit)
            } else {
                Text(markerName(marker))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }

        if marker.hasUnit {
            // Tapping a colleague that is part of a unit opens the unit info.
            NavigationLink(value: LiveMapRoute.unit(marker.unit.id)) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Label for a marker whose user belongs to a unit: the unit's alias with a
    /// status-colored dot instead of the colleague's full name.
    private func unitMarkerLabel(_ unit: Resources_Centrum_Units_Unit) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(unit.status.status.color)
                .frame(width: 5, height: 5)
            Text(unit.initials.isEmpty ? unit.name : unit.initials)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    private func dispatchMarkerView(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> some View {
        // Dedicated (typed) route instead of a bare Int64 so the marker tap
        // resolves unambiguously in the enclosing stack (bare Int64 collides
        // with the Wiki page destination and can double-push a module).
        NavigationLink(value: LiveMapRoute.dispatch(dispatch.id)) {
            VStack(spacing: 2) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(dispatch.status.status.color.readableText)
                    .frame(width: 22, height: 22)
                    .background(dispatch.status.status.color, in: Circle())
                    .shadow(radius: 2)
                Text(formatDispatchID(dispatch.id))
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
    }

    private func markerName(_ marker: Resources_Livemap_Markers_UserMarker) -> String {
        let override = marker.data.nameOverride
        if marker.hasData, marker.data.hasNameOverride, !override.firstname.isEmpty || !override.lastname.isEmpty {
            let name = [override.firstname, override.lastname].filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty { return name }
        }
        let user = marker.user
        let name = [user.firstname, user.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Benutzer #\(marker.userID)" : name
    }

    private func markerColor(_ marker: Resources_Livemap_Markers_UserMarker) -> Color {
        Color(hex: marker.color) ?? .accentColor
    }

    private func markerMarkerColor(_ marker: Resources_Livemap_Markers_MarkerMarker) -> Color {
        marker.hasColor ? (Color(hex: marker.color) ?? .accentColor) : .accentColor
    }

    // MARK: - Units tab

    private var unitsTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(sortedUnits) { unit in
                    UnitTileView(unit: unit)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .overlay {
            if appState.units.isEmpty {
                ContentUnavailableView(
                    "Keine Einheiten",
                    systemImage: "building.2",
                    description: Text("Es sind keine Einheiten verfügbar.")
                )
            }
        }
    }

    /// All units, favorites first.
    private var sortedUnits: [Resources_Centrum_Units_Unit] {
        let favorites = appState.favoriteUnitIDs
        return appState.units.sorted { lhs, rhs in
            let l = favorites.contains(lhs.id)
            let r = favorites.contains(rhs.id)
            if l != r { return l }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - Marker marker details

/// Detail sheet for a marker marker (zone/area): name, description, expiry and
/// creator.
private struct MarkerMarkerDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let marker: Resources_Livemap_Markers_MarkerMarker

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        headerIcon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(marker.name.isEmpty ? "Markierung #\(marker.id)" : marker.name)
                                .font(.headline)
                            Text(marker.type.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if marker.hasDescription_p, !marker.description_p.isEmpty {
                    Section("Beschreibung") {
                        Text(marker.description_p)
                            .font(.subheadline)
                    }
                }

                Section("Details") {
                    detailRow("Postleitzahl", marker.postal.isEmpty ? "k.A." : marker.postal)
                    if let expires = marker.expiry {
                        detailRow("Läuft ab am", formatTimestamp(expires))
                    }
                    detailRow("Erstellt von", creatorName)
                    detailRow("Erstellt am", formatTimestamp(marker.createdAt))
                    detailRow("Job", marker.jobLabel.isEmpty ? "k.A." : marker.jobLabel)
                }
            }
            .navigationTitle("Markierung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var markerColor: Color {
        marker.hasColor ? (Color(hex: marker.color) ?? .accentColor) : .accentColor
    }

    /// Shown in the header: the marker's own icon marker with the icon,
    /// or a plain colored circle when the marker has no icon.
    @ViewBuilder
    private var headerIcon: some View {
        if marker.type == .icon {
            MapMarkerIconView(icon: detailIconName, color: markerColor, size: 22)
                .frame(width: 44, height: 44)
                .background(markerColor.opacity(0.15), in: Circle())
        } else {
            Circle()
                .fill(markerColor)
                .frame(width: 40, height: 40)
        }
    }

    private var detailIconName: String {
        guard marker.hasData, let data = marker.data.data, case .icon(let icon) = data else {
            return "mdi:map-marker-question"
        }
        return icon.icon.isEmpty ? "mdi:map-marker-question" : icon.icon
    }

    private var creatorName: String {
        guard marker.hasCreator else { return "Unbekannt" }
        let name = [marker.creator.firstname, marker.creator.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Unbekannt" : name
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

extension Resources_Livemap_Markers_MarkerMarker {
    /// Convenience expiry accessor.
    var expiry: Resources_Timestamp_Timestamp? {
        hasExpiresAt ? expiresAt : nil
    }
}

// MARK: - Map projection (mirrors FiveNet's custom CRS)

private enum MapProjection {
    static let scaleX: Double = 0.02072
    static let scaleY: Double = 0.0205
    static let centerX: Double = 117.3
    static let centerY: Double = 172.8
    static let tileSize: Double = 256
    static let minZoom = 1
    static let maxZoom = 7

    static func project(_ point: CGPoint, zoom: Int) -> CGPoint {
        let scale = pow(2.0, Double(zoom))
        return CGPoint(
            x: (point.x * scaleX + centerX) * scale,
            y: (point.y * -scaleY + centerY) * scale
        )
    }

    static func unproject(_ pixel: CGPoint, zoom: Int) -> CGPoint {
        let scale = pow(2.0, Double(zoom))
        return CGPoint(
            x: (pixel.x / scale - centerX) / scaleX,
            y: (pixel.y / scale - centerY) / -scaleY
        )
    }
}

extension Resources_Livemap_Markers_MarkerType {
    var label: String {
        switch self {
        case .unspecified: return "Unbekannt"
        case .dot: return "Punkt"
        case .circle: return "Kreis"
        case .icon: return "Symbol"
        case .rectangle: return "Rechteck"
        case .polygon: return "Polygon"
        case .polyline: return "Polylinie"
        case .UNRECOGNIZED: return "Unbekannt"
        }
    }
}

// MARK: - Tile loading

/// Loads a single map tile from the FiveNet server with on-disk-free in-memory caching.
private struct MapTileView: View {
    let url: URL
    let backgroundColor: Color

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            backgroundColor
            if let image {
                Image(uiImage: image)
                    .resizable()
            }
        }
        .task(id: url) {
            image = await MapTileCache.shared.image(for: url)
        }
    }
}

@MainActor
private final class MapTileCache {
    static let shared = MapTileCache()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) {
            return hit
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}

#Preview {
    NavigationStack {
        LiveMapView()
            .environment(AppState())
    }
}

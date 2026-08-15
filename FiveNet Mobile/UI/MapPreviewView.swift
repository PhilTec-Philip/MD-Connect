import SwiftUI

/// Small read-only map preview centered on a world coordinate.
/// Mirrors the FiveNet custom CRS used by the LiveMap.
struct MapPreviewView: View {
    let worldPoint: CGPoint
    let baseURL: URL?
    var zoom: Int = 4

    private var projection: MapPreviewProjection { .init() }

    var body: some View {
        GeometryReader { geo in
            let tileSize = projection.tileSize
            let worldPixel = projection.project(worldPoint, zoom: zoom)
            let tileX = Int(floor(worldPixel.x / tileSize))
            let tileY = Int(floor(worldPixel.y / tileSize))
            let offsetX = worldPixel.x - CGFloat(tileX) * tileSize
            let offsetY = worldPixel.y - CGFloat(tileY) * tileSize
            let cols = Int(ceil(geo.size.width / tileSize)) + 2
            let rows = Int(ceil(geo.size.height / tileSize)) + 2
            let startX = tileX - cols / 2
            let startY = tileY - rows / 2
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2

            ZStack {
                Color(hex: "74aace")
                ForEach(startX ..< startX + cols, id: \.self) { x in
                    ForEach(startY ..< startY + rows, id: \.self) { y in
                        MapPreviewTileView(url: tileURL(x: x, y: y))
                            .frame(width: tileSize, height: tileSize)
                            .position(
                                x: centerX - offsetX + CGFloat(x - tileX) * tileSize + tileSize / 2,
                                y: centerY - offsetY + CGFloat(y - tileY) * tileSize + tileSize / 2
                            )
                    }
                }
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Palette.danger)
                    .shadow(radius: 2)
                    .position(x: centerX, y: centerY)
            }
            .clipped()
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func tileURL(x: Int, y: Int) -> URL {
        let base = baseURL ?? URL(string: "https://localhost")!
        return base.appendingPathComponent("images/livemap/tiles/postal/\(zoom)/\(x)/\(y).webp")
    }
}

private struct MapPreviewTileView: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(hex: "74aace")
            if let image {
                Image(uiImage: image)
                    .resizable()
            }
        }
        .task(id: url) {
            image = await MapPreviewTileCache.shared.image(for: url)
        }
    }
}

/// Caches decoded map tiles in memory (mirrors the LiveMap tile cache).
private actor MapPreviewTileCache {
    static let shared = MapPreviewTileCache()

    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) -> UIImage? {
        if let cached = cache[url] { return cached }
        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else { return nil }
            cache[url] = image
            return image
        } catch {
            return nil
        }
    }
}

/// Custom CRS used by the FiveNet LiveMap (mirrors `MapProjection` in LiveMapView).
private struct MapPreviewProjection {
    let scaleX: Double = 0.02072
    let scaleY: Double = 0.0205
    let centerX: Double = 117.3
    let centerY: Double = 172.8
    let tileSize: Double = 256

    func project(_ point: CGPoint, zoom: Int) -> CGPoint {
        let scale = pow(2.0, Double(zoom))
        return CGPoint(
            x: (point.x * scaleX + centerX) * scale,
            y: (point.y * -scaleY + centerY) * scale
        )
    }
}

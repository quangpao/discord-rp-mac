import AppKit
import DiscordRP
import SwiftUI

/// Fetches image bytes once per URL and keeps them for the session, so flipping between presets
/// does not re-download the same GIF.
@MainActor
final class PreviewCache {
    static let shared = PreviewCache()
    private var storage: [String: Data] = [:]

    func data(for url: URL) -> Data? { storage[url.absoluteString] }

    func load(_ url: URL) async throws -> Data {
        if let cached = data(for: url) { return cached }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PreviewError.http(http.statusCode)
        }
        guard !data.isEmpty else { throw PreviewError.empty }
        storage[url.absoluteString] = data
        return data
    }
}

enum PreviewError: Error, CustomStringConvertible {
    case http(Int)
    case empty
    case notAnImage

    var description: String {
        switch self {
        case .http(let status): "HTTP \(status)"
        case .empty: "empty response"
        case .notAnImage: "not an image"
        }
    }
}

/// An `NSImageView` so animated GIFs actually animate — SwiftUI's `Image`/`AsyncImage` would only
/// ever show the first frame, which is exactly what makes a GIF hard to identify.
///
/// An `NSImageView` reports the image's **natural size** as its fitting size, so left alone SwiftUI
/// sizes it to e.g. 480×480 inside a 64 pt box and clips the overflow. It is pinned to the box
/// instead: low hugging/compression resistance, aspect-fit scaling, centred.
struct AnimatedImageView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard view.image == nil || context.coordinator.loadedData != data else { return }
        context.coordinator.loadedData = data
        view.image = NSImage(data: data)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedData: Data?
    }
}

/// The thumbnail shown under an image key, with the facts needed to tell what it is without
/// applying the preset and looking at Discord.
struct ImagePreview: View {
    let key: String
    let appID: String
    /// Numeric asset id from the assets API — required to preview a Discord asset name.
    var assetID: String? = nil
    /// Side of the square preview box.
    var side: CGFloat = 96
    /// Extra note (e.g. how Discord renders this slot on the card).
    var note: String?

    @State private var data: Data?
    @State private var failure: String?
    @State private var loading = false

    private var target: PreviewTarget? { PreviewTarget.make(key: key, appID: appID, assetID: assetID) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            box
                // One fixed column for every preview, so the captions of the large and small rows
                // start at the same x even though the boxes are different sizes.
                .frame(width: 96, height: side, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let target {
                    Text(target.kind + (data.map { " · " + sizeText($0) } ?? ""))
                        .font(.system(size: 11, weight: .semibold))
                    if let data {
                        Text(pixelText(data)).font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if let failure {
                        Text(failure).font(.system(size: 11)).foregroundStyle(.red)
                    } else if loading {
                        Text("loading…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(target.url.absoluteString)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("No preview").font(.system(size: 11, weight: .semibold))
                    Text(noPreviewReason).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: key + "|" + appID + "|" + (assetID ?? "")) { await load() }
    }

    private var noPreviewReason: String {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Empty — nothing to show." }
        if appID.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Needs the Application ID from the Connection card."
        }
        return "Discord serves asset images by numeric id, not by name — press “Load from Discord” in the Asset names row to resolve it."
    }

    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            if let data {
                AnimatedImageView(data: data)
                    // Pin the view to the box: the NSImageView must not be sized by the image's own
                    // natural size, or a 480 px GIF overflows a 64 pt preview.
                    .frame(width: side - 8, height: side - 8)
                    .clipped()
            } else if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: failure == nil ? "photo" : "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func load() async {
        guard let target else {
            data = nil
            failure = nil
            return
        }
        if let cached = PreviewCache.shared.data(for: target.url) {
            data = cached
            failure = nil
            return
        }
        data = nil
        failure = nil
        loading = true
        do {
            let bytes = try await PreviewCache.shared.load(target.url)
            guard NSImage(data: bytes) != nil else { throw PreviewError.notAnImage }
            data = bytes
        } catch {
            failure = error is PreviewError
                ? (error as? PreviewError)?.description ?? "failed"
                : "Could not load (\((error as NSError).code))"
        }
        loading = false
    }

    /// Byte size — enough to spot a 4 MB GIF before Discord chokes on it.
    private func sizeText(_ data: Data) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    /// Real pixel size of the image, so a tiny source is obvious before it is scaled on the card.
    private func pixelText(_ data: Data) -> String {
        guard let image = NSImage(data: data) else { return "" }
        return "\(Int(image.size.width))×\(Int(image.size.height)) px"
    }
}

import SwiftUI
import UIKit

/// One day of history snapshots from `GET /snaps?date=` (the TV keeps 7 days).
struct SnapDay: Codable, Equatable {
    struct Snap: Codable, Equatable, Identifiable, Hashable {
        var time: Double
        var app: String
        var label: String
        var name: String

        var id: String { name }
        var date: Date { Date(timeIntervalSince1970: time / 1000) }
    }

    var date: String
    var keepDays: Int
    var snaps: [Snap]
    var days: [String]

    func snaps(in span: ActivityDay.Span) -> [Snap] {
        snaps.filter { $0.time >= span.start - 1000 && $0.time <= span.end + 1000 && $0.app == span.app }
    }
}

/// Snapshots already seen stay on the phone too (same 7 days), so they open while the TV is off.
enum SnapCache {
    private static let memory = NSCache<NSString, UIImage>()

    private static var dir: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("snaps")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(_ day: String, _ name: String) -> URL {
        let d = dir.appendingPathComponent(day)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(name)
    }

    static func image(_ day: String, _ name: String) -> UIImage? {
        let key = "\(day)/\(name)" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: file(day, name)), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    static func store(_ data: Data, _ day: String, _ name: String) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        try? data.write(to: file(day, name), options: .atomic)
        memory.setObject(image, forKey: "\(day)/\(name)" as NSString)
        return image
    }

    static func saveList(_ data: Data, for day: String) {
        try? data.write(to: file(day, "list.json"), options: .atomic)
    }

    static func list(_ day: String) -> SnapDay? {
        guard let data = try? Data(contentsOf: file(day, "list.json")) else { return nil }
        return try? JSONDecoder().decode(SnapDay.self, from: data)
    }

    /// Drops day folders older than the TV keeps them.
    static func prune(keepDays: Int = 7) {
        let oldest = DayKey.string(Calendar.current.date(byAdding: .day, value: -(keepDays - 1), to: Date()) ?? Date())
        let days = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for d in days where d < oldest {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(d))
        }
    }
}

/// A thumbnail that loads its JPEG from the phone cache or the TV.
struct SnapThumb: View {
    @EnvironmentObject private var tv: RemoteModel
    let day: String
    let snap: SnapDay.Snap
    var width: CGFloat = 132
    var caption = true
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.1)))
            if caption {
                Text(snap.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                + Text("  " + snap.label).font(.caption2).foregroundStyle(.white)
            }
        }
        .frame(width: width, alignment: .leading)
        .lineLimit(1)
        .task(id: snap.name) {
            if image == nil { image = await tv.snapImage(day: day, snap.name) }
            failed = image == nil
        }
    }
}

/// Full screen, swipe between the day's snapshots.
struct SnapViewer: View {
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.dismiss) private var dismiss
    let day: String
    let snaps: [SnapDay.Snap]
    @State var selection: String

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(snaps) { snap in
                    SnapPage(day: day, snap: snap).tag(snap.name)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: snaps.count > 1 && snaps.count <= 30 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let image = SnapCache.image(day, selection) {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image)))
                    }
                }
            }
        }
    }

    private var title: String {
        guard let snap = snaps.first(where: { $0.name == selection }) else { return "" }
        return "\(snap.label) · \(snap.date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct SnapPage: View {
    @EnvironmentObject private var tv: RemoteModel
    let day: String
    let snap: SnapDay.Snap
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 8)
            } else {
                ProgressView()
            }
            Text(snap.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .task(id: snap.name) { image = await tv.snapImage(day: day, snap.name) }
    }
}

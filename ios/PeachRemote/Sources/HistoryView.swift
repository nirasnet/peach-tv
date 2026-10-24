import SwiftUI

/// "Today" on the main screen: screen time and the top apps; tap for the full history.
struct TodayCard: View {
    @EnvironmentObject private var tv: RemoteModel

    var body: some View {
        NavigationLink {
            HistoryView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Today", systemImage: "chart.bar.xaxis").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Text(tv.today.map { Duration.text($0.onSeconds) } ?? "—")
                        .font(.headline).foregroundStyle(Peach.peach)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let day = tv.today, !day.totals.isEmpty {
                    let top = Array(day.totals.prefix(3))
                    let maximum = max(top.first?.seconds ?? 1, 1)
                    ForEach(top) { total in
                        AppBar(total: total, maximum: maximum)
                    }
                } else {
                    Text("TV on/off times and which app ran when. Tap to see each day.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressStyle())
    }
}

struct AppBar: View {
    let total: ActivityDay.Total
    let maximum: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(total.label).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text(Duration.text(total.seconds)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Peach.peach, Peach.coral], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * CGFloat(total.seconds) / CGFloat(maximum)))
                    }
            }
            .frame(height: 6)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var tv: RemoteModel
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var result: RemoteModel.ActivityResult?
    @State private var snapDay: SnapDay?
    @State private var viewing: SnapDay.Snap?

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dayPicker
                switch result {
                case .live(let day):
                    content(day)
                case .saved(let day, let saved):
                    Label("TV is off · saved \(saved.formatted(date: .omitted, time: .shortened))", systemImage: "icloud.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                    content(day)
                case .unavailable(let reason):
                    empty(reason)
                case nil:
                    ProgressView().padding(40)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .refreshable { await load() }
        .background(PeachBackground())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: date) { await load() }
        .fullScreenCover(item: $viewing) { snap in
            if let snapDay {
                SnapViewer(day: snapDay.date, snaps: snapDay.snaps, selection: snap.name)
            }
        }
    }

    @ViewBuilder
    private var snapshots: some View {
        if let snapDay, !snapDay.snaps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Snapshots").font(.headline)
                    Spacer()
                    Text("every 10 min · kept \(snapDay.keepDays) days").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(snapDay.snaps.reversed()) { snap in
                            Button { viewing = snap } label: { SnapThumb(day: snapDay.date, snap: snap) }
                                .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
        }
    }

    private var dayPicker: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            Spacer()
            VStack(spacing: 2) {
                Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(date.formatted(.dateTime.day().month(.wide).year()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .overlay {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden().blendMode(.destinationOver).opacity(0.02)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(isToday)
        }
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Peach.card))
    }

    @ViewBuilder
    private func content(_ day: ActivityDay) -> some View {
        if day.sessions.isEmpty && day.marks.isEmpty {
            empty(day.days.isEmpty || (day.days.first.map { $0 > day.date } ?? false)
                  ? "No history yet for this day. The TV started keeping it on \(firstDay(day))."
                  : "The TV was off all day 🌙")
        } else {
            summary(day)
            if !day.totals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Apps").font(.headline)
                    let maximum = max(day.totals.first?.seconds ?? 1, 1)
                    ForEach(day.totals) { AppBar(total: $0, maximum: maximum) }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
            }
            snapshots
            VStack(alignment: .leading, spacing: 0) {
                Text("Timeline").font(.headline).padding(.bottom, 10)
                let items = day.timeline
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TimelineRow(item: item, last: index == items.count - 1,
                                snapDay: snapDay, open: { viewing = $0 })
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
        }
    }

    private func summary(_ day: ActivityDay) -> some View {
        let first = day.sessions.first?.startDate
        let last = day.sessions.last
        return HStack(spacing: 0) {
            Stat(title: "Screen time", value: Duration.text(day.onSeconds), tint: Peach.peach)
            Divider().frame(height: 36).overlay(Color.white.opacity(0.1))
            Stat(title: "First on", value: first.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", tint: Peach.online)
            Divider().frame(height: 36).overlay(Color.white.opacity(0.1))
            Stat(title: last?.ongoing == true ? "Still on" : "Last off",
                 value: last.map { $0.ongoing ? "now" : $0.endDate.formatted(date: .omitted, time: .shortened) } ?? "—",
                 tint: Peach.coral)
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
    }

    private func empty(_ text: String) -> some View {
        VStack(spacing: 10) {
            Text("🍑").font(.system(size: 44))
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
    }

    private func firstDay(_ day: ActivityDay) -> String {
        guard let key = day.days.first, let d = DayKey.date(key) else { return "the day the agent was installed" }
        return d.formatted(.dateTime.day().month(.wide))
    }

    private func shift(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date), next <= Date() else { return }
        date = next
    }

    private func load() async {
        let key = DayKey.string(date)
        if case .live(let day) = result, day.date == key {} else { result = nil }
        if snapDay?.date != key { snapDay = nil }
        async let snaps = tv.snaps(for: date)
        result = await tv.activity(for: date)
        snapDay = await snaps
    }
}

struct Stat: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TimelineRow: View {
    let item: TimelineItem
    let last: Bool
    var snapDay: SnapDay?
    var open: (SnapDay.Snap) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            VStack(spacing: 0) {
                Circle().fill(tint).frame(width: 10, height: 10).padding(.top, 5)
                if !last { Rectangle().fill(Color.white.opacity(0.1)).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if case .app(let span) = item.kind, let snapDay {
                    let shots = snapDay.snaps(in: span)
                    if !shots.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(shots) { snap in
                                    Button { open(snap) } label: {
                                        SnapThumb(day: snapDay.date, snap: snap, width: 96, caption: false)
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 14)
            Spacer(minLength: 0)
        }
    }

    private var time: String { item.time.formatted(date: .omitted, time: .shortened) }

    private var title: String {
        switch item.kind {
        case .on: return "📺 TV on"
        case .off: return "🌙 TV off"
        case .lock: return "🔒 Locked from the phone"
        case .unlock: return "🔓 Unlocked"
        case .rule(let text): return text
        case .app(let span): return span.label ?? span.app ?? "App"
        }
    }

    private var detail: String? {
        guard case .app(let span) = item.kind else { return nil }
        let from = span.startDate.formatted(date: .omitted, time: .shortened)
        let to = span.ongoing ? "now" : span.endDate.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to) · \(Duration.text(span.seconds))"
    }

    private var tint: Color {
        switch item.kind {
        case .on: return Peach.online
        case .off: return .gray
        case .lock, .unlock, .rule: return Peach.coral
        case .app: return Peach.peach
        }
    }
}

enum Duration {
    static func text(_ seconds: Int) -> String {
        if seconds < 60 { return seconds <= 0 ? "0 m" : "<1 m" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }
}

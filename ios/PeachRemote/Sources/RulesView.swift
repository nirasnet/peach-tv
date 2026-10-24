import SwiftUI

/// Main-screen card: one switch for the rules, what is left today, and quick extra time.
struct RulesCard: View {
    @EnvironmentObject private var tv: RemoteModel

    var body: some View {
        if let state = tv.rules {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass").font(.title3.weight(.semibold)).foregroundStyle(Peach.peach)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family rules").font(.headline)
                        Text(summary(state)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.rules.enabled },
                        set: { on in Task { await tv.setRulesEnabled(on) } }))
                        .labelsHidden()
                        .tint(Peach.coral)
                }
                if state.rules.enabled {
                    TodayMeter(state: state)
                    HStack(spacing: 8) {
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button { Task { await tv.addBonus(minutes: minutes) } } label: {
                                Text(minutes == 60 ? "+1 h" : "+\(minutes) min")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(Capsule().fill(Peach.peach.opacity(0.15)))
                            }
                            .buttonStyle(PressStyle())
                        }
                        Button { Task { await tv.pauseToday(!state.today.paused) } } label: {
                            Image(systemName: state.today.paused ? "play.fill" : "pause.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 36)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .disabled(!tv.isOnline || tv.busy != nil)
                }
                NavigationLink { RulesView() } label: {
                    HStack {
                        Text("Edit TV hours & screen time").font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Peach.peach)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(state.rules.enabled ? Peach.coral.opacity(0.35) : Color.white.opacity(0.08)))
        }
    }

    private func summary(_ state: RulesState) -> String {
        guard state.rules.enabled else { return "Off · tap the switch to limit TV time" }
        let t = state.today
        if t.paused { return "Paused today · back on at midnight" }
        if t.blocked == "schedule" { return "Locked · TV time is \(Clock.text(t.from))–\(Clock.text(t.to))" }
        if t.blocked == "limit" { return "Locked · today's screen time is used up" }
        var parts: [String] = []
        if state.rules.schedule.enabled { parts.append("\(Clock.text(t.from))–\(Clock.text(t.to))") }
        if state.rules.limit.enabled { parts.append("\(Clock.limit(t.limitSec / 60)) a day") }
        if let left = t.remainingSec { parts.append("\(Duration.text(left)) left") }
        return parts.joined(separator: " · ")
    }
}

/// Screen time bar for today (used of limit + bonus).
struct TodayMeter: View {
    let state: RulesState

    var body: some View {
        let t = state.today
        let allowed = max(t.limitSec + t.bonusSec, 1)
        let fraction = min(Double(t.usedSec) / Double(allowed), 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Screen time today").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(state.rules.limit.enabled
                     ? "\(Duration.text(t.usedSec)) of \(Duration.text(allowed))"
                     : Duration.text(t.usedSec))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if state.rules.limit.enabled {
                GeometryReader { geo in
                    Capsule().fill(Color.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: fraction > 0.85 ? [Peach.coral, .red] : [Peach.online, Peach.peach],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * fraction))
                        }
                }
                .frame(height: 8)
            }
        }
    }
}

struct RulesView: View {
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FamilyRules?
    @State private var confirmLock = false

    private static let limits = [30, 45, 60, 90, 120, 180]

    var body: some View {
        Form {
            if let binding = Binding($draft) {
                Section {
                    Toggle("Family rules on", isOn: binding.enabled).tint(Peach.coral)
                } footer: {
                    Text("The TV enforces these by itself, even when your phone is away or the internet is down.")
                }

                if binding.wrappedValue.lockOffMin != nil {
                    Section {
                        NavigationLink { LookView() } label: {
                            Label("Theme & wording", systemImage: "paintpalette")
                        }
                        Picker("Turn TV off when locked for", selection: Binding(
                            get: { binding.wrappedValue.lockOffMin ?? 10 },
                            set: { binding.wrappedValue.lockOffMin = $0 })) {
                            Text("Never").tag(0)
                            ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    } header: {
                        Text("Lock screen")
                    } footer: {
                        Text("Nobody watches a lock screen: any lock (yours or a rule's) left on this long puts the TV to standby. Works even with the family rules off.")
                    }
                }

                Section {
                    Toggle("Only allow TV between…", isOn: binding.schedule.enabled).tint(Peach.coral)
                    if binding.wrappedValue.schedule.enabled {
                        TimeRange(title: "Mon – Fri", from: binding.schedule.weekdayFrom, to: binding.schedule.weekdayTo)
                        TimeRange(title: "Sat – Sun", from: binding.schedule.weekendFrom, to: binding.schedule.weekendTo)
                    }
                } header: {
                    Text("TV hours")
                } footer: {
                    Text("Outside these hours the TV shows a 🌙 lock screen. A warning pops up 5 minutes and 1 minute before.")
                }

                Section {
                    Toggle("Limit screen time", isOn: binding.limit.enabled).tint(Peach.coral)
                    if binding.wrappedValue.limit.enabled {
                        LimitPicker(title: "Mon – Fri", minutes: binding.limit.weekdayMin, options: Self.limits)
                        LimitPicker(title: "Sat – Sun", minutes: binding.limit.weekendMin, options: Self.limits)
                    }
                } header: {
                    Text("Screen time per day")
                } footer: {
                    Text("Counts only while the screen is on and unlocked; the screensaver doesn't count. Resets at midnight.")
                }

                Section {
                    Toggle("Turn the TV off 5 min after time is up", isOn: binding.turnOff).tint(Peach.coral)
                } footer: {
                    Text("Saves power. Turning it back on still shows the lock screen until TV time comes back.")
                }

                Section("Recommended") {
                    Button {
                        draft = FamilyRules(enabled: true, turnOff: true, lockOffMin: draft?.lockOffMin ?? 10,
                                            schedule: .init(enabled: true, weekdayFrom: 7 * 60, weekdayTo: 20 * 60 + 30,
                                                            weekendFrom: 8 * 60, weekendTo: 21 * 60),
                                            limit: .init(enabled: true, weekdayMin: 60, weekendMin: 120))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("School-age kids 🎒").foregroundStyle(.white)
                            Text("Mon–Fri 07:00–20:30 · 1 h a day\nSat–Sun 08:00–21:00 · 2 h a day · TV off when time's up")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Tips: keep the last hour before bed screen-free. Use +15 min as a reward instead of raising the limit. A parent can unlock with the arrow code on the remote: that pauses the rules until midnight.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachBackground())
        .navigationTitle("TV time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if locksNow { confirmLock = true } else { save() }
                }
                .disabled(draft == nil || draft == tv.rules?.rules || tv.busy != nil)
            }
        }
        .confirmationDialog("This locks the TV now", isPresented: $confirmLock, titleVisibility: .visible) {
            Button("Save and lock") { save() }
        } message: {
            if let t = tv.rules?.today {
                Text("The TV was already on for \(Duration.text(t.usedSec)) today, which is over the new limit. Time used today still counts.")
            }
        }
        .task {
            if tv.rules == nil { await tv.loadRules() }
            if draft == nil { draft = tv.rules?.rules }
        }
    }
}

extension RulesView {
    private func save() {
        guard let draft else { return }
        Task { if await tv.saveRules(draft) { dismiss() } }
    }

    /// True when the new limit is at or below today's TV time and the TV isn't locked for it already.
    private var locksNow: Bool {
        guard let draft, let state = tv.rules, draft.enabled, draft.limit.enabled else { return false }
        let t = state.today
        if t.paused { return false }
        let minutes = t.weekend ? draft.limit.weekendMin : draft.limit.weekdayMin
        let lockedAlready = state.rules.enabled && state.rules.limit.enabled && (t.remainingSec ?? 1) <= 0
        return !lockedAlready && t.usedSec >= minutes * 60 + t.bonusSec
    }
}

struct TimeRange: View {
    let title: String
    @Binding var from: Int
    @Binding var to: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            DatePicker("", selection: minutes($from), displayedComponents: .hourAndMinute).labelsHidden()
            Text("–").foregroundStyle(.secondary)
            DatePicker("", selection: minutes($to), displayedComponents: .hourAndMinute).labelsHidden()
        }
    }

    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: { Clock.date(value.wrappedValue) }, set: { value.wrappedValue = Clock.minutes($0) })
    }
}

struct LimitPicker: View {
    let title: String
    @Binding var minutes: Int
    let options: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(Clock.limit(minutes)).foregroundStyle(Peach.peach).monospacedDigit()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button { minutes = option } label: {
                            Text(Clock.limit(option))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(option == minutes ? Peach.coral : Color.white.opacity(0.08)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderless)
                    }
                    Stepper("", value: $minutes, in: 5...600, step: 15).labelsHidden()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

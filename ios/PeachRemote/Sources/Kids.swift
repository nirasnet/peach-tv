import SwiftUI

/// GET/POST /kids (agent 1.6+): kids mode shows and allows only the chosen apps (AIS PLAY by default).
struct KidsState: Decodable, Equatable {
    struct App: Decodable, Equatable, Identifiable {
        var pkg: String
        var label: String
        var id: String { pkg }
    }
    var enabled: Bool
    var auto: Bool
    var apps: [String]
    var available: [App]

    func label(_ pkg: String) -> String {
        available.first { $0.pkg == pkg }?.label ?? pkg
    }

    var appNames: String {
        apps.isEmpty ? "nothing" : apps.map(label).joined(separator: ", ")
    }
}

// MARK: - Main screen card

struct KidsCard: View {
    @EnvironmentObject private var tv: RemoteModel

    var body: some View {
        if let on = tv.kids?.enabled ?? tv.status?.kidsMode {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(on ? "🧸" : "👨‍👩‍👧").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(on ? "Kids mode" : "Parent mode").font(.headline)
                        Text(summary(on)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    modeButton("🧸 Kids", selected: on) { Task { await tv.setKidsMode(true) } }
                    modeButton("👨‍👩‍👧 Parent", selected: !on) { Task { await tv.setKidsMode(false) } }
                }
                .disabled(!tv.isOnline || tv.busy != nil)
                NavigationLink { KidsAppsView() } label: {
                    HStack {
                        Text("Choose kids apps").font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Peach.peach)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(on ? Peach.online.opacity(0.35) : Peach.coral.opacity(0.35)))
            .animation(.spring(duration: 0.35), value: on)
        }
    }

    private func summary(_ on: Bool) -> String {
        guard let kids = tv.kids else { return on ? "Only the kids apps" : "All apps" }
        if on { return "TV shows only \(kids.appNames)" }
        return kids.auto ? "All apps · back to Kids mode when the TV turns off" : "All apps until you switch back"
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(selected ? Peach.peach : Color.white.opacity(0.1)))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Apps editor

struct KidsAppsView: View {
    @EnvironmentObject private var tv: RemoteModel

    var body: some View {
        List {
            if let kids = tv.kids {
                Section {
                    Toggle("Kids mode", isOn: Binding(
                        get: { kids.enabled },
                        set: { on in Task { await tv.setKidsMode(on) } }))
                    Toggle("Back to Kids mode when the TV turns off", isOn: Binding(
                        get: { kids.auto },
                        set: { on in Task { await tv.saveKids(["auto": on], done: on ? "Parent mode ends when the TV turns off" : "Parent mode stays until you switch") } }))
                } footer: {
                    Text("In Kids mode the TV home shows only the apps below, with no Settings or Inputs. Any other app (or Settings) goes straight back to Home.")
                }
                Section("Allowed in Kids mode") {
                    ForEach(kids.available) { app in
                        Toggle(isOn: Binding(
                            get: { kids.apps.contains(app.pkg) },
                            set: { on in Task { await toggle(app, on: on, in: kids) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.label)
                                Text(app.pkg).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Peach.online)
                    }
                }
            } else {
                Section {
                    HStack { ProgressView(); Text("Asking the TV…").foregroundStyle(.secondary) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachBackground())
        .navigationTitle("Kids apps")
        .disabled(!tv.isOnline || tv.busy != nil)
        .task { await tv.loadKids() }
        .refreshable { await tv.loadKids() }
    }

    private func toggle(_ app: KidsState.App, on: Bool, in kids: KidsState) async {
        var apps = kids.apps.filter { $0 != app.pkg }
        if on { apps.append(app.pkg) }
        await tv.saveKids(["apps": apps], done: on ? "\(app.label) allowed for kids ✅" : "\(app.label) hidden from kids")
    }
}

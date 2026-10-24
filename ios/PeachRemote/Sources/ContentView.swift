import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showLock = false
    @State private var showMessage = false
    @State private var confirmOff = false
    @State private var showSnapshot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusCard()
                    actions
                    KidsCard()
                    RulesCard()
                    SnapshotCard(showFull: $showSnapshot)
                    TodayCard()
                    Text("Look Peach Family 🍑")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .refreshable { await tv.refresh() }
            .background(PeachBackground())
            .navigationTitle("Peach TV")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLock) { TextPickerSheet(mode: .lock) }
        .sheet(isPresented: $showMessage) { TextPickerSheet(mode: .message) }
        .fullScreenCover(isPresented: $showSnapshot) { SnapshotViewer() }
        .confirmationDialog("Turn off the TV?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { Task { await tv.turnOff() } }
        } message: {
            Text("It goes to standby. Turning it back on needs the TV remote.")
        }
        .alert("Join the family TV? 🍑", isPresented: Binding(
            get: { tv.pendingInvite != nil },
            set: { if !$0 { tv.pendingInvite = nil } })) {
            Button("Join") {
                if let invite = tv.pendingInvite { Task { await tv.accept(invite) } }
                tv.pendingInvite = nil
            }
            Button("Cancel", role: .cancel) { tv.pendingInvite = nil }
        } message: {
            Text("This iPhone will be able to check, lock and turn off the TV from anywhere.")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            tv.setActive(phase == .active)
        }
    }

    private var actions: some View {
        let online = tv.isOnline
        let screenOn = tv.status?.screenOn ?? false
        let locked = tv.status?.locked ?? false
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            if online && !screenOn {
                ActionTile(title: "Wake", subtitle: "Screen on", symbol: "sun.max.fill", tint: Peach.peach) {
                    Task { await tv.wake() }
                }
            } else {
                ActionTile(title: "Turn Off", subtitle: "Standby", symbol: "power", tint: Peach.coral) {
                    confirmOff = true
                }
                .disabled(!online)
            }
            if locked {
                ActionTile(title: "Unlock",
                           subtitle: tv.status?.lockReason == "parent" || tv.status?.lockReason == nil ? "Let them watch" : "Rules off till midnight",
                           symbol: "lock.open.fill", tint: Peach.online) {
                    Task { await tv.unlock() }
                }
                .disabled(!online)
            } else {
                ActionTile(title: "Lock", subtitle: "With a message", symbol: "lock.fill", tint: Peach.peach) {
                    showLock = true
                }
                .disabled(!online)
            }
            ActionTile(title: "Snap", subtitle: "See the screen", symbol: "camera.fill", tint: Peach.cream) {
                Task { await tv.takeSnapshot() }
            }
            .disabled(!online || !screenOn)
            ActionTile(title: "Message", subtitle: "Pop-up on TV", symbol: "bubble.left.fill", tint: Peach.cream) {
                showMessage = true
            }
            .disabled(!online)
        }
        .disabled(tv.busy != nil)
    }
}

// MARK: - Status

struct StatusCard: View {
    @EnvironmentObject private var tv: RemoteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 58, height: 58)
                        .shadow(color: tint.opacity(0.6), radius: tv.isOnline ? 14 : 0)
                    Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if tv.busy != nil || tv.connection == .checking {
                    ProgressView()
                }
            }
            if let status = tv.status, tv.isOnline {
                Divider().overlay(Color.white.opacity(0.1))
                InfoRow(label: "On screen", value: onScreen(status))
                InfoRow(label: "Lock", value: lockText(status))
                if let volume = status.volume {
                    InfoRow(label: "Volume", value: (status.muted ?? false) ? "Muted" : "\(volume)%")
                }
                if let uptime = status.uptimeSec {
                    InfoRow(label: "Up for", value: Self.duration(uptime))
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Peach.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(tint.opacity(0.25)))
        .animation(.spring(duration: 0.4), value: tv.connection)
    }

    private var tint: Color {
        switch tv.connection {
        case .online: return tv.status?.screenOn == false ? Peach.peach : Peach.online
        case .offline: return .gray
        case .checking: return Peach.peach
        }
    }

    private var icon: String {
        switch tv.connection {
        case .online: return tv.status?.locked == true ? "lock.tv.fill" : "tv.fill"
        case .offline: return "tv.slash"
        case .checking: return "tv"
        }
    }

    private var title: String {
        switch tv.connection {
        case .checking: return "Checking…"
        case .offline: return "TV is off"
        case .online: return tv.status?.screenOn == false ? "Screen off" : "TV is on"
        }
    }

    private var subtitle: String {
        switch tv.connection {
        case .checking: return "Looking for the TV"
        case .online(let host, let ms):
            let via = tv.viaBuiltInTailscale ? "built-in Tailscale" : TVSettings.describe(host: host)
            return "Online via \(via) · \(ms) ms"
        case .offline:
            if case .connecting = tv.tailnet { return "Connecting from away…" }
            guard let seen = tv.lastSeen else { return "Off or unreachable" }
            return "Last seen \(seen.formatted(.relative(presentation: .named)))"
        }
    }

    private func lockText(_ status: TVStatus) -> String {
        guard status.locked else { return "Unlocked" }
        switch status.lockReason {
        case "schedule": return "Locked 🌙 outside TV hours"
        case "limit": return "Locked ⏰ time's up"
        default: return "Locked 🔒"
        }
    }

    private func onScreen(_ status: TVStatus) -> String {
        if !status.screenOn { return "Nothing (screen off)" }
        if let label = status.appLabel, !label.isEmpty { return label }
        return "Home"
    }

    static func duration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.day, .hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(seconds)) ?? "—"
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1)
        }
        .font(.subheadline)
    }
}

struct ActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Peach.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08)))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Snapshot

struct SnapshotCard: View {
    @EnvironmentObject private var tv: RemoteModel
    @Binding var showFull: Bool

    var body: some View {
        if let image = tv.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                Button { showFull = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12)))
                }
                .buttonStyle(PressStyle())
                if let time = tv.snapshotTime {
                    Text("Snapped \(time.formatted(date: .omitted, time: .shortened)) · tap to share")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SnapshotViewer: View {
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = tv.snapshot {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let image = tv.snapshot {
                        let picture = Image(uiImage: image)
                        ShareLink(item: picture, preview: SharePreview("TV snapshot", image: picture))
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { Task { await tv.takeSnapshot() } } label: {
                        Label("Snap again", systemImage: "camera.fill")
                    }
                    .disabled(tv.busy != nil)
                }
            }
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    @EnvironmentObject private var tv: RemoteModel

    var body: some View {
        if let text = tv.toast {
            Text(text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Peach.peach.opacity(0.4)))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { tv.toast = nil }
                .animation(.spring(duration: 0.35), value: tv.toast)
        }
    }
}

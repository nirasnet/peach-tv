import SwiftUI

/// Pick a preset or type your own: used for the lock screen text and for pop-up messages.
struct TextPickerSheet: View {
    enum Mode { case lock, message }

    let mode: Mode
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var templates: [String] = []
    @State private var saved: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section(mode == .lock ? "Lock screen says" : "Quick messages") {
                    ForEach(templates, id: \.self) { text in
                        Button { submit(text) } label: {
                            HStack {
                                if saved.contains(text) { Image(systemName: "star.fill").font(.caption).foregroundStyle(Peach.peach) }
                                Text(text).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: mode == .lock ? "lock.fill" : "paperplane.fill")
                                    .foregroundStyle(Peach.peach)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { custom = text } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                            if saved.contains(text) {
                                Button(role: .destructive) {
                                    Templates.remove(text, field)
                                    reload()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
                Section {
                    Text("Your own").font(.footnote).foregroundStyle(.secondary)
                    TextField(mode == .lock ? "Message on the lock screen" : "Message to show on the TV",
                              text: $custom, axis: .vertical)
                        .lineLimit(1...3)
                    Button(mode == .lock ? "Lock TV" : "Send") { submit(custom) }
                        .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        Templates.save(custom, field)
                        reload()
                    } label: { Label("Save as my template", systemImage: "star") }
                        .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || templates.contains(custom))
                } footer: {
                    Text("Swipe a line left to edit it, or to delete one of your ★ templates.")
                }
                if mode == .lock {
                    Section {
                        NavigationLink { LookView() } label: {
                            Label("Lock screen theme & wording", systemImage: "paintpalette")
                        }
                    }
                    Section {
                        Text("Locked TVs ignore the remote (volume still works). Unlock from here, or type the unlock code with the remote's arrows; see Settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PeachBackground())
            .navigationTitle(mode == .lock ? "Lock the TV" : "Send a message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: reload)
    }

    private var field: Templates.Field { mode == .lock ? .lock : .message }

    private func reload() {
        templates = Templates.all(field)
        saved = Templates.saved(field)
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismiss()
        Task {
            switch mode {
            case .lock: await tv.lock(message: trimmed)
            case .message: await tv.send(message: trimmed)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TVSettings(tailscaleHost: "", lanHost: "", port: 8765, token: "")
    @State private var unlockCode: String?
    @State private var showToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Tailscale") {
                        TextField("100.x.y.z", text: $draft.tailscaleHost).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Home Wi-Fi") {
                        TextField("192.168.1.x", text: $draft.lanHost).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Port") {
                        TextField("8765", value: $draft.port, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Where the TV is")
                } footer: {
                    Text("Tailscale is the TV's address on the family tailnet. Away from home it works through the built-in Tailscale (below), or the Tailscale app.")
                }
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Section {
                    HStack {
                        Group {
                            if showToken { TextField("Token", text: $draft.token) } else { SecureField("Token", text: $draft.token) }
                        }
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        Button { showToken.toggle() } label: { Image(systemName: showToken ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Token")
                } footer: {
                    Text("tv-agent/install.sh prints it. Anyone with it can lock the TV, so keep it private.")
                }

                Section {
                    NavigationLink { AwayView() } label: {
                        LabeledContent("Away from home") {
                            Text(tv.tailnet == .notSetUp ? "Set up" : "On ✅")
                        }
                    }
                } footer: {
                    Text("Use the TV from anywhere, without the Tailscale app. Invite the family here too.")
                }

                Section {
                    LabeledContent("Unlock code on the remote") {
                        Text(unlockCode.map(arrows) ?? "—").font(.title3)
                    }
                } footer: {
                    Text("If the phone is away, unlock the TV by pressing these arrows on the TV remote while the lock screen shows.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PeachBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        tv.apply(draft)
                        dismiss()
                    }
                    .disabled(draft.hosts.isEmpty || draft.token.isEmpty)
                }
            }
            .onAppear { draft = tv.settings }
            .task { unlockCode = await tv.unlockCode() }
        }
    }

    private func arrows(_ code: String) -> String {
        code.map { c -> String in
            switch c {
            case "U": return "↑"
            case "D": return "↓"
            case "L": return "←"
            case "R": return "→"
            default: return String(c)
            }
        }.joined(separator: " ")
    }
}

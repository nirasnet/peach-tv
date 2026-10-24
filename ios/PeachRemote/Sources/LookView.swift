import SwiftUI

/// Theme, background and wording of the TV lock screen, with templates and a preview on the TV.
struct LookView: View {
    @EnvironmentObject private var tv: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LockLook?
    @State private var kind: Kind = .schedule

    enum Kind: String, CaseIterable, Identifiable {
        case parent, schedule, limit, warn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .parent: return "Parent lock"
            case .schedule: return "TV hours"
            case .limit: return "Time's up"
            case .warn: return "Warning"
            }
        }
    }

    private static let emojis = ["🍑", "🌙", "🐳", "🌳", "🌸", "🌅", "🚀", "🍭", "🧸", "🦖", "🐱", "🐶", "🐰", "🦄",
                                 "⭐️", "📚", "😴", "🛁", "🎨", "⚽️", "❤️", "🏡"]

    var body: some View {
        Form {
            if let binding = Binding($draft) {
                let d = binding.wrappedValue
                let k = kind == .warn ? "parent" : kind.rawValue
                let st = d.style(k)
                let theme = LockTheme.named(st.theme)
                let sb = Binding<LockStyle>(get: { draft?.style(k) ?? st },
                                            set: { draft?.setStyle($0, for: k) })
                Section {
                    Picker("Show", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    if kind == .warn {
                        WarnPreview(text: Templates.sample(d.warnText, rules: tv.rules))
                            .listRowBackground(Color.clear)
                    } else {
                        LockPreview(theme: theme, emoji: st.emoji, message: previewMessage(d),
                                    sub: previewSub(d), sprinkle: st.sprinkle)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Button {
                        Task { await tv.previewLook(d, kind: kind.rawValue) }
                    } label: {
                        Label("Preview on the TV (10 s)", systemImage: "tv")
                    }
                    .disabled(!tv.isOnline || tv.busy != nil)
                }

                if kind != .warn {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(LockTheme.all) { t in
                                Button {
                                    sb.wrappedValue.theme = t.id
                                    sb.wrappedValue.emoji = ""
                                } label: {
                                    VStack(spacing: 5) {
                                        LockPreview(theme: t, message: "", sub: "", sprinkle: st.sprinkle)
                                            .frame(width: 128)
                                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(t.id == st.theme ? Peach.coral : Color.white.opacity(0.1),
                                                        lineWidth: t.id == st.theme ? 3 : 1))
                                        Text(t.name).font(.caption)
                                            .foregroundStyle(t.id == st.theme ? Peach.peach : .secondary)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Big picture").font(.subheadline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                chip("Theme \(theme.emoji)", selected: st.emoji.isEmpty) { sb.wrappedValue.emoji = "" }
                                ForEach(Self.emojis, id: \.self) { e in
                                    chip(e, selected: st.emoji == e) { sb.wrappedValue.emoji = e }
                                }
                            }
                        }
                        TextField("Or type any emoji", text: sb.emoji)
                            .onChange(of: st.emoji) { _, new in
                                if new.count > 2 { sb.wrappedValue.emoji = String(new.prefix(2)) }
                            }
                    }
                    Toggle("Little \(theme.sprinkle.isEmpty ? "decorations" : theme.sprinkle) in the background", isOn: sb.sprinkle)
                        .tint(Peach.coral)
                    Toggle("Big picture floats gently", isOn: sb.animate).tint(Peach.coral)
                    Button {
                        binding.wrappedValue.setStyleForAll(st)
                    } label: {
                        Label("Use this look for all lock screens", systemImage: "square.on.square")
                    }
                    .disabled(Kind.allCases.dropLast().allSatisfy { d.style($0.rawValue) == st })
                } header: {
                    Text("\(kind.title) · theme & background")
                } footer: {
                    Text("Parent lock, TV hours and Time's up each keep their own look. Switch above to change another.")
                }
                } else {
                    Section {
                        Text("The warning is a small pop-up over the show; it has no background to choose.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                WordingSection(title: "Outside TV hours", field: .scheduleText, text: binding.scheduleText,
                               hint: "{from} {to} become today's TV hours.") { kind = .schedule }
                WordingSection(title: "Screen time used up", field: .limitText, text: binding.limitText,
                               hint: "{limit} becomes today's screen time, e.g. 1 ชั่วโมง.") { kind = .limit }
                WordingSection(title: "Warning before time runs out", field: .warnText, text: binding.warnText,
                               hint: "{min} becomes the minutes left (5, then 1).") { kind = .warn }
                WordingSection(title: "Small line under a parent lock", field: .parentSub, text: binding.parentSub,
                               hint: "The big text of a parent lock is chosen when you press Lock.", allowEmpty: true) { kind = .parent }
            } else if tv.look == nil && !tv.isOnline {
                Text("Turn the TV on to change its lock screen.").foregroundStyle(.secondary)
            } else if tv.lookUnsupported {
                Text("Update the TV agent (tv-agent/install.sh) to change the lock screen.").foregroundStyle(.secondary)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachBackground())
        .navigationTitle("Lock screen look")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let draft else { return }
                    Task { if await tv.saveLook(draft) { dismiss() } }
                }
                .disabled(draft == nil || draft == tv.look || tv.busy != nil)
            }
        }
        .task {
            await tv.loadLook()
            if draft == nil { draft = tv.look }
        }
    }

    private func previewMessage(_ d: LockLook) -> String {
        switch kind {
        case .parent: return tv.status?.lockReason == "parent" ? (tv.status?.lockMessage ?? "") : "ถึงเวลาพักสายตาแล้วนะ"
        case .schedule: return Templates.sample(d.scheduleText, rules: tv.rules)
        case .limit, .warn: return Templates.sample(d.limitText, rules: tv.rules)
        }
    }

    private func previewSub(_ d: LockLook) -> String {
        let t = tv.rules?.today
        switch kind {
        case .parent: return d.parentSub
        case .schedule: return "TV TIME \(Clock.text(t?.from ?? 420)) – \(Clock.text(t?.to ?? 1230))"
        case .limit, .warn: return "SCREEN TIME \(Templates.sample("{limit}", rules: tv.rules)) · SEE YOU TOMORROW"
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.title3)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selected ? Peach.coral.opacity(0.8) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.borderless)
    }
}

/// The peach pop-up as the TV shows it.
private struct WarnPreview: View {
    let text: String
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 8) {
                Text("🍑")
                Text(text).font(.caption).foregroundStyle(Peach.cream).lineLimit(2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .overlay(Capsule().stroke(Peach.peach.opacity(0.6)))
            .padding(.top, 12)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A text field with tap-to-use templates; your own can be saved and long-pressed to delete.
struct WordingSection: View {
    let title: String
    let field: Templates.Field
    @Binding var text: String
    var hint: String
    var allowEmpty = false
    var focus: () -> Void = {}
    @State private var list: [String] = []
    @State private var saved: [String] = []

    var body: some View {
        Section {
            TextField(allowEmpty ? "(empty: no small line)" : "Your words", text: $text, axis: .vertical)
                .lineLimit(1...3)
                .onTapGesture(perform: focus)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list, id: \.self) { t in
                        Button {
                            text = t
                            focus()
                        } label: {
                            HStack(spacing: 4) {
                                if saved.contains(t) { Image(systemName: "star.fill").font(.caption2) }
                                Text(t.isEmpty ? "(none)" : t).font(.footnote).lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(t == text ? Peach.coral.opacity(0.85) : Color.white.opacity(0.08)))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderless)
                        .contextMenu {
                            if saved.contains(t) {
                                Button(role: .destructive) {
                                    Templates.remove(t, field)
                                    reload()
                                } label: { Label("Delete template", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            Button {
                Templates.save(text, field)
                reload()
            } label: {
                Label("Save as my template", systemImage: "star")
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || list.contains(text))
        } header: {
            Text(title)
        } footer: {
            Text(hint + " Long-press a ★ template to delete it.")
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        list = Templates.all(field)
        saved = Templates.saved(field)
    }
}

import CoreImage.CIFilterBuiltins
import SwiftUI

/// Settings → Away from home: the built-in Tailscale on this iPhone, and invites for the family.
struct AwayView: View {
    @EnvironmentObject private var tv: RemoteModel
    @State private var inviteKey = Keychain.read(account: Keychain.inviteKey) ?? ""
    @State private var confirmLeave = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { Text(stateText).foregroundStyle(stateColor) }
                if tv.tailnet == .notSetUp {
                    PasteButton(payloadType: URL.self) { urls in
                        guard let url = urls.first else { return }
                        Task { @MainActor in tv.open(url) }
                    }
                    .tint(Peach.peach)
                } else {
                    Button("Remove from this iPhone", role: .destructive) { confirmLeave = true }
                }
            } header: {
                Text("This iPhone")
            } footer: {
                Text(tv.tailnet == .notSetUp
                     ? "Got an invite from the family? Scan its QR code with the Camera app, or copy the invite link and tap Paste."
                     : "Works on any internet (4G/5G, other Wi-Fi) while the app is open. No Tailscale app or VPN switch needed.")
            }

            Section {
                SecureField("tskey-auth-…", text: $inviteKey)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: inviteKey) { _, key in
                        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { Keychain.delete(account: Keychain.inviteKey) }
                        else { Keychain.write(trimmed, account: Keychain.inviteKey) }
                    }
                if validKey {
                    if tv.tailnet == .notSetUp {
                        Button("Set up on this iPhone") { Task { await tv.join(authKey: trimmedKey) } }
                    }
                    NavigationLink("Invite family 💌") { InviteView(authKey: trimmedKey) }
                }
            } header: {
                Text("Invite key (parents)")
            } footer: {
                Text("A reusable, pre-approved Tailscale auth key with the tag:peachphone tag (Tailscale admin console → Settings → Keys). It stays on this iPhone and goes into the invites you make.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PeachBackground())
        .navigationTitle("Away from home")
        .disabled(tv.busy != nil)
        .confirmationDialog("Remove away-from-home access?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await tv.leaveTailnet() } }
        } message: {
            Text("The TV will only answer on the home Wi-Fi. Delete this iPhone in the Tailscale admin console too.")
        }
    }

    private var trimmedKey: String { inviteKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validKey: Bool { trimmedKey.hasPrefix("tskey-") }

    private var stateText: String {
        switch tv.tailnet {
        case .notSetUp: return "Not set up"
        case .off: return "Ready ✅"
        case .connecting: return "Connecting…"
        case .connected: return "Connected ✅"
        case .failed(let message): return message
        }
    }

    private var stateColor: Color {
        switch tv.tailnet {
        case .off, .connected: return Peach.online
        case .failed: return Peach.coral
        default: return .secondary
        }
    }
}

/// A QR code and a link holding everything a family member needs: scan with the Camera app, tap, done.
struct InviteView: View {
    @EnvironmentObject private var tv: RemoteModel
    let authKey: String

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let url = Invite.url(authKey: authKey, settings: tv.settings), let qr = Self.qr(url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                        .frame(maxWidth: 300)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("วิธีใช้ (ทำครั้งเดียว)").font(.headline)
                        Text("1. ติดตั้งแอป Peach TV จาก TestFlight")
                        Text("2. เปิดกล้อง iPhone ส่องคิวอาร์นี้ แล้วแตะ \"เปิดใน Peach TV\"")
                        Text("3. แตะ \"เข้าร่วม\" เสร็จแล้ว ใช้ได้ทุกที่ ✨")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Peach.card))
                    ShareLink(item: url, message: Text("ชวนใช้ Peach TV 🍑 แตะลิงก์นี้บน iPhone ที่ติดตั้งแอปแล้ว (หรือคัดลอกแล้วกด Paste ในแอป)")) {
                        Label("Send the invite link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Peach.peach)
                    .foregroundStyle(.black)
                    Text("The invite carries the TV key: send it only to family.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(PeachBackground())
        .navigationTitle("Invite family")
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

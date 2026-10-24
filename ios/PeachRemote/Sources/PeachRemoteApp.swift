import SwiftUI

@main
struct PeachRemoteApp: App {
    @StateObject private var model = RemoteModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Peach.peach)
                .onOpenURL { url in model.open(url) }
        }
    }
}

enum Peach {
    static let peach = Color(red: 1.0, green: 0.70, blue: 0.54)
    static let coral = Color(red: 1.0, green: 0.47, blue: 0.40)
    static let cream = Color(red: 1.0, green: 0.95, blue: 0.90)
    static let card = Color.white.opacity(0.07)
    static let online = Color(red: 0.42, green: 0.86, blue: 0.55)

    static let lockPresets = [
        "ถึงเวลาพักสายตาแล้วนะ",
        "ไปทำการบ้านก่อนนะ 📚",
        "มากินข้าวกันจ้า 🍚",
        "ได้เวลานอนแล้ว 😴",
    ]
    static let messagePresets = [
        "มากินข้าวกันจ้า 🍚",
        "อีก 10 นาทีปิดทีวีนะ ⏰",
        "ลงมาข้างล่างหน่อยจ้า",
        "รักนะ 🍑",
    ]
}

struct PeachBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.07, blue: 0.06), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Peach.peach.opacity(0.18), .clear],
                           center: .init(x: 0.5, y: 0.05), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

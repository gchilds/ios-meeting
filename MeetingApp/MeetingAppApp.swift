import SwiftUI

@main
struct MeetingAppApp: App {
    @StateObject private var store = TranscriptStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

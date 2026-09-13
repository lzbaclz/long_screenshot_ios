import SwiftUI

@main
struct ScrollCaptureApp: App {
    @StateObject private var library = CaptureLibrary()
    @StateObject private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
                .environmentObject(purchases)
                .preferredColorScheme(.light)
                .task { await purchases.start() }
                .task {
                    while !Task.isCancelled {
                        if scenePhase == .active { library.refresh() }
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { library.refresh() }
                }
        }
    }
}

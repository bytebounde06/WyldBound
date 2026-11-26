import SwiftUI

@main
struct WyldBoundApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .background(Color(red: 0.23, green: 0.18, blue: 0.43))
        }
    }
}

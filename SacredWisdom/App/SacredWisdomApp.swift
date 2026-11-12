import SwiftUI

@main
struct SacredWisdomApp: App {
    private let dependencies = AppSession.shared.dependencies
    private let coordinator = AppSession.shared.coordinator
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView(dependencies: dependencies, coordinator: coordinator)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(dependencies.preferences.appearance.colorScheme)
            .task {
                try? await Task.sleep(for: dependencies.configuration.splashDuration)
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}

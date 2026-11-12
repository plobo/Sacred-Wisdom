import Foundation

/// The single set of dependencies and navigation state for the process. The SwiftUI app and App Intents
/// (which Siri may run while the app is in the background or not yet on screen) share it.
@MainActor
final class AppSession {
    static let shared = AppSession()

    let dependencies: AppDependencies
    let coordinator: AppCoordinator

    init(dependencies: AppDependencies = .live(), coordinator: AppCoordinator = AppCoordinator()) {
        self.dependencies = dependencies
        self.coordinator = coordinator
    }

    var intentService: ScriptureIntentService { dependencies.makeIntentService() }
}

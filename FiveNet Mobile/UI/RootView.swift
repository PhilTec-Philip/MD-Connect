import SwiftUI

/// Routes between the auth phases and the main overview.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appViewMode") private var viewMode: AppViewMode = .overview

    var body: some View {
        Group {
            switch appState.phase {
            case .setupServer:
                ServerSetupView()
            case .serverPicker:
                ServerPickerView()
            case .login:
                LoginView()
            case .chooseCharacter:
                CharacterSelectView()
            case .overview:
                switch viewMode {
                case .overview:
                    OverviewView()
                case .quick:
                    QuickView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.phase)
        .animation(.easeInOut(duration: 0.2), value: viewMode)
    }
}

#Preview {
    RootView()
        .environment(AppState())
}

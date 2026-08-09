import SwiftUI

/// Routes between the auth phases and the main overview.
struct RootView: View {
    @Environment(AppState.self) private var appState

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
                OverviewView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.phase)
    }
}

#Preview {
    RootView()
        .environment(AppState())
}

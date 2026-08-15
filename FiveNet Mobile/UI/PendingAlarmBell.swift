import SwiftUI

/// Yellow animated alarm bell shown in the navigation bar while a dispatch
/// assigned to the own unit still awaits the user's accept/decline (e.g. the
/// alarm screen was closed via the X button). Tapping it re-opens the alarm.
struct PendingAlarmBell: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.pendingAlarmDispatch != nil, appState.activeAlarm == nil {
            Button {
                appState.reopenPendingAlarm()
            } label: {
                Image(systemName: "bell.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .symbolEffect(.pulse)
                    .accessibilityLabel("Offener Einsatz wartet auf Bestätigung")
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: appState.pendingAlarmDispatch?.id)
        }
    }
}

#Preview {
    NavigationStack {
        Text("Meine Einheit")
            .pendingAlarmBell()
    }
    .environment(AppState())
}

/// Adds the pending-alarm bell as a leading navigation-bar item. The bell only
/// renders while a dispatch assigned to the own unit awaits accept/decline.
struct PendingAlarmBellToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PendingAlarmBell()
            }
        }
    }
}

extension View {
    func pendingAlarmBell() -> some View {
        modifier(PendingAlarmBellToolbar())
    }
}

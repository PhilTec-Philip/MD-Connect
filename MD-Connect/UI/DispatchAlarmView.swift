import SwiftUI

/// Fullscreen red alarm shown when the character's own unit is assigned to a
/// dispatch. Shows the dispatch location (with a mini map), sender and status,
/// plus large "Annehmen" / "Ablehnen" buttons.
struct DispatchAlarmView: View {
    @Environment(AppState.self) private var appState

    let alarm: DispatchAlarm

    @State private var isHandling = false

    private var dispatch: Resources_Centrum_Dispatches_Dispatch {
        alarm.dispatch
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.05, blue: 0.05), Theme.Palette.danger.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                header
                locationCard
                senderCard
                Spacer(minLength: Theme.Spacing.sm)
                actionButtons
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        appState.dismissAlarm()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Alarm schließen")
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.sm)
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .symbolEffect(.bounce, value: alarm.id)
            Text("NEUER EINSATZ")
                .font(Theme.Typography.title2)
                .tracking(2)
            Text(formatDispatchID(dispatch.id))
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.white.opacity(0.2), in: Capsule())
            if let message = dispatchMessageText(dispatch) {
                Text(message)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Label(dispatch.status.status.label, systemImage: "circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dispatch.status.status.color)
        }
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Standort", systemImage: "mappin.and.ellipse")
                .font(.subheadline.bold())
            if dispatch.x != 0 || dispatch.y != 0 {
                MapPreviewView(
                    worldPoint: CGPoint(x: dispatch.x, y: dispatch.y),
                    baseURL: appState.client?.baseURL
                )
                .frame(height: 120)
            }
            if !dispatch.postal.isEmpty {
                Label(dispatch.postal, systemImage: "number")
                    .font(.subheadline)
            }
            Text(standortKoordinate)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    private var senderCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Gesendet von", systemImage: "person.crop.circle")
                .font(.subheadline.bold())
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: dispatch.anon ? "eye.slash.fill" : "person.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.2), in: Circle())
                Text(senderText)
                    .font(.subheadline.weight(.medium))
            }
            if !dispatch.description_p.isEmpty {
                Text(dispatch.description_p)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Button {
                handle(.accepted)
            } label: {
                actionLabel(
                    title: isHandling ? "Bearbeite …" : "Annehmen",
                    systemImage: "checkmark"
                )
            }
            .buttonStyle(.plain)
            .disabled(isHandling)

            Button {
                handle(.declined)
            } label: {
                actionLabel(
                    title: isHandling ? "Bearbeite …" : "Ablehnen",
                    systemImage: "xmark"
                )
            }
            .buttonStyle(.plain)
            .disabled(isHandling)
        }
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(.white)
        .background(
            systemImage == "xmark" ? Color.black.opacity(0.35) : Theme.Palette.success.opacity(0.85),
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
    }

    private var senderText: String {
        if dispatch.anon {
            return "Anonym"
        }
        let user = dispatch.creator
        let name = [user.firstname, user.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Unbekannt" : name
    }

    private var standortKoordinate: String {
        guard dispatch.x != 0 || dispatch.y != 0 else { return "Keine Koordinaten angegeben" }
        return "Position: \(Int(dispatch.x)), \(Int(dispatch.y))"
    }

    private func handle(_ resp: Resources_Centrum_Dispatches_TakeDispatchResp) {
        guard !isHandling else { return }
        isHandling = true
        Task { @MainActor in
            await appState.takeDispatch(dispatch.id, resp: resp)
            appState.dismissAlarm()
        }
    }
}

#Preview {
    DispatchAlarmView(alarm: DispatchAlarm(id: 1, dispatch: Resources_Centrum_Dispatches_Dispatch()))
        .environment(AppState())
}

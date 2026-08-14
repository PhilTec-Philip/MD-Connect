import SwiftUI

/// Fullscreen red alarm shown when the character's own unit is assigned to a
/// dispatch. Shows the dispatch location (with a mini map), sender and status,
/// plus large "Annehmen" / "Ablehnen" buttons.
///
/// Renders a yellow "Verstärkung" variant for `needAssistance` alarms.
struct DispatchAlarmView: View {
    @Environment(AppState.self) private var appState

    let alarm: DispatchAlarm

    @State private var isHandling = false

    private var isReinforcement: Bool {
        alarm.kind == .reinforcement
    }

    private var dispatch: Resources_Centrum_Dispatches_Dispatch {
        alarm.dispatch
    }

    private var gradientColors: [Color] {
        if isReinforcement {
            return [Color(red: 0.72, green: 0.52, blue: 0.03), Color(red: 0.88, green: 0.62, blue: 0.08).opacity(0.8)]
        }
        return [Color(red: 0.62, green: 0.05, blue: 0.05), Theme.Palette.danger.opacity(0.75)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
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
                    if !isReinforcement {
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
            Image(systemName: isReinforcement ? "exclamationmark.bubble.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .symbolEffect(.bounce, value: alarm.id)
            Text(isReinforcement ? "VERSTÄRKUNG ANFORDERN" : "NEUER EINSATZ")
                .font(Theme.Typography.title2)
                .tracking(2)
            Text(formatDispatchID(dispatch.id))
                .font(.headline)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.white.opacity(0.2), in: Capsule())
            if isReinforcement {
                Text("Eine Einheit vor Ort braucht Unterstützung.")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
            }
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
            Label(isReinforcement ? "Hilferufendes Kollegium" : "Gesendet von", systemImage: "person.2.fill")
                .font(.subheadline.bold())
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: isReinforcement ? "exclamationmark.bubble.fill" : (dispatch.anon ? "person.crop.circle.badge.questionmark" : "person.fill"))
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
        if isReinforcement {
            return AnyView(Button {
                appState.dismissAlarm()
            } label: {
                actionLabel(
                    title: "Schließen",
                    systemImage: "xmark"
                )
            }
            .buttonStyle(.plain))
        }
        return AnyView(HStack(spacing: Theme.Spacing.xl) {
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
        })
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
        if isReinforcement {
            if let requester = alarm.requester {
                return colleagueName(requester)
            }
            return dispatch.anon ? "Anonym" : creatorName
        }
        if dispatch.anon {
            return "Anonym"
        }
        return creatorName
    }

    private var creatorName: String {
        let user = dispatch.creator
        let name = [user.firstname, user.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Unbekannt" : name
    }

    private func colleagueName(_ colleague: Resources_Jobs_Colleagues_Colleague) -> String {
        let name = [colleague.firstname, colleague.lastname].filter { !$0.isEmpty }.joined(separator: " ")
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

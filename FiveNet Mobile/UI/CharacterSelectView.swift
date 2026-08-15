import SwiftUI

/// Character picker shown after a successful login.
struct CharacterSelectView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xxxl) {
                    Spacer(minLength: 24)

                    VStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.Palette.accent, Color(red: 0.10, green: 0.29, blue: 0.69)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 84, height: 84)
                        .shadow(color: Theme.Palette.accent.opacity(0.35), radius: 16, y: 8)

                        VStack(spacing: Theme.Spacing.xs) {
                            Text("Charakter wählen")
                                .font(Theme.Typography.title)
                            Text("Wähle den Charakter, mit dem du dich verbinden möchtest.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.xl)], spacing: Theme.Spacing.xl) {
                        ForEach(appState.characters) { character in
                            Button {
                                Task {
                                    await appState.chooseCharacter(id: character.char.userID)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                    HStack {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.tint)
                                        Spacer()
                                        if appState.busy == .choosingCharacter {
                                            ProgressView()
                                        }
                                    }
                                    Text(displayName(character))
                                        .font(Theme.Typography.headline)
                                        .foregroundStyle(.primary)
                                    if let job = jobLine(character) {
                                        Text(job)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(Theme.Spacing.xl)
                                .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                                .background(Theme.Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.busy != .none)
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, Theme.Spacing.xs)

                    if let error = appState.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                            .font(.callout)
                            .padding(Theme.Spacing.lg)
                            .background(Theme.Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }

                    Button("Abmelden") {
                        Task { await appState.logout() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)

                    Spacer(minLength: 24)
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func displayName(_ character: Resources_Accounts_Character) -> String {
        let name = [character.char.firstname, character.char.lastname]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Unbenannter Charakter" : name
    }

    private func jobLine(_ character: Resources_Accounts_Character) -> String? {
        var parts: [String] = []
        if !character.char.jobLabel.isEmpty {
            parts.append(character.char.jobLabel)
        }
        if !character.char.jobGradeLabel.isEmpty {
            parts.append(character.char.jobGradeLabel)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    CharacterSelectView()
        .environment(AppState())
}

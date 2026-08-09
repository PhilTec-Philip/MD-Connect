import SwiftUI

/// Login screen: credentials are exchanged for an account token (fivenet_acc).
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    private enum Field {
        case username
        case password
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xxxl) {
                    Spacer(minLength: 40)

                    VStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.Palette.accent, Color(red: 0.10, green: 0.29, blue: 0.69)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 88, height: 88)
                        .shadow(color: Theme.Palette.accent.opacity(0.35), radius: 16, y: 8)

                        VStack(spacing: Theme.Spacing.xs) {
                            Text("MD-Connect")
                                .font(Theme.Typography.largeTitle)
                            if let server = appState.session.serverURL {
                                Label(server.host ?? server.absoluteString, systemImage: "server.rack")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(spacing: Theme.Spacing.lg) {
                        VStack(spacing: Theme.Spacing.lg) {
                            TextField("Benutzername", text: $username)
                                .textFieldStyle(.plain)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .username)
                                .onSubmit { focusedField = .password }
                                .padding(Theme.Spacing.lg)
                                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

                            SecureField("Passwort", text: $password)
                                .textFieldStyle(.plain)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .onSubmit(submit)
                                .padding(Theme.Spacing.lg)
                                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        }
                        .frame(maxWidth: 480)

                        Button {
                            submit()
                        } label: {
                            Group {
                                if appState.busy == .login {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Anmelden")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: 480)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.busy != .none || username.isEmpty || password.isEmpty)
                        .frame(maxWidth: 480)

                        Button("Anderen Server verwenden") {
                            appState.changeServer()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }

                    if let error = appState.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                            .font(.callout)
                            .frame(maxWidth: 480)
                            .padding(Theme.Spacing.lg)
                            .background(Theme.Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }

                    Spacer(minLength: 40)
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: prefillDemoCredentials)
    }

    /// Auf dem Demo-Server werden die öffentlichen Zugangsdaten vorbelegt, damit
    /// man direkt nach dem Login den Charakter auswählen kann.
    private func prefillDemoCredentials() {
        guard appState.session.isDemoServerActive else { return }
        if username.isEmpty {
            username = "demo"
        }
        if password.isEmpty {
            password = "fivenet-demo"
        }
    }

    private func submit() {
        focusedField = nil
        Task {
            await appState.login(username: username, password: password)
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}

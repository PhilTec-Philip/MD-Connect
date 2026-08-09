import SwiftUI

/// First-run screen: asks for the FiveNet server address.
struct ServerSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.bottom, 8)

            Text("MD-Connect")
                .font(.largeTitle.bold())

            VStack(spacing: 10) {
                Text("Verbindung zu deinem FiveNet-Server herstellen.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    appState.submitServerURL(AuthSessionStore.demoServer.absoluteString)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Demo-Server starten")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .fontWeight(.semibold)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Text("Der offizielle FiveNet-Demo-Server. Ohne eigene Zugangsdaten testen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)

            HStack {
                Rectangle()
                    .fill(Theme.Palette.placeholder)
                    .frame(height: 1)
                Text("oder eigener Server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Theme.Palette.placeholder)
                    .frame(height: 1)
            }
            .frame(maxWidth: 480)

            VStack(spacing: 10) {
                TextField("fivenet.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onSubmit(continueTapped)

                Button {
                    continueTapped()
                } label: {
                    Text("Weiter")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 480)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: 480)
            }
            .frame(maxWidth: 480)

            if let error = appState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.danger)
                    .font(.callout)
                    .frame(maxWidth: 480)
            }

            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private func continueTapped() {
        appState.submitServerURL(serverURL)
    }
}

#Preview {
    ServerSetupView()
        .environment(AppState())
}

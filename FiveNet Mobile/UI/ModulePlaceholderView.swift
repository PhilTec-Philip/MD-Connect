import SwiftUI

/// Placeholder shown when a module is selected. Native document rendering is
/// planned for a later milestone.
struct ModulePlaceholderView: View {
    let module: FiveNetModule

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: module.icon)
                .font(.system(size: 56))
                .foregroundStyle(module.tint)
                .padding(.bottom, 4)

            Text(module.title)
                .font(.title.bold())

            Text("Dieses Modul wird in einer späteren Version von FiveNet Mobile unterstützt.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ModulePlaceholderView(module: .citizens)
    }
}

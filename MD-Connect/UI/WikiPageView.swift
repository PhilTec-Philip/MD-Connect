import SwiftUI

/// Displays a single wiki page: its metadata, the page tree for navigation,
/// and the rendered content.
struct WikiPageView: View {
    @Environment(AppState.self) private var appState

    let pageID: Int64

    @State private var page: Resources_Wiki_Page?
    @State private var tree: [Resources_Wiki_PageShort] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showTree = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxl) {
                if let errorMessage {
                    SectionCard {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }

                if isLoading && page == nil {
                    SectionCard {
                        ProgressView("Seite wird geladen …")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }

                if let page {
                    header(page)

                    if isRootPage(page) {
                        treeSection(pages: tree, currentID: page.id)
                    }

                    if page.hasContent {
                        WikiContentView(content: page.content)
                            .padding(.top, 4)
                    } else {
                        SectionCard {
                            Text("Diese Seite hat noch keinen Inhalt.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(page?.meta.title.isEmpty == false ? page!.meta.title : "Wiki")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    /// A page is a wiki root (and shows the TOC) when it is explicitly flagged
    /// as startpage or appears at the top level of the page tree.
    private func isRootPage(_ page: Resources_Wiki_Page) -> Bool {
        page.meta.startpage || tree.contains { $0.id == page.id }
    }

    // MARK: - Sections

    private func treeSection(pages: [Resources_Wiki_PageShort], currentID: Int64) -> some View {
        let ancestors = Self.ancestorIDs(of: currentID, in: pages)
        return Group {
            if !pages.isEmpty {
                DisclosureGroup(isExpanded: $showTree) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pages) { node in
                            WikiTreeNodeView(page: node, currentID: currentID, ancestors: ancestors)
                        }
                    }
                    .padding(.top, Theme.Spacing.sm)
                } label: {
                    Label("Inhaltsverzeichnis", systemImage: "list.bullet.indent")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }
        }
    }

    private func header(_ page: Resources_Wiki_Page) -> some View {
        DetailHero(
            gradient: FiveNetModule.wiki.gradient,
            icon: FiveNetModule.wiki.icon,
            title: page.meta.title.isEmpty ? "Unbenannt" : page.meta.title,
            subtitle: page.meta.description_p.isEmpty ? nil : page.meta.description_p,
            badges: heroBadges(page)
        )
    }

    private func heroBadges(_ page: Resources_Wiki_Page) -> [String] {
        var result: [String] = []
        result.append(jobLabel(page))
        result.append(contentsOf: metaBadges(page).map(\.title))
        return result
    }

    private func jobLabel(_ page: Resources_Wiki_Page) -> String {
        let label = page.hasJobLabel && !page.jobLabel.isEmpty ? page.jobLabel : page.job
        return label.isEmpty ? "Wiki" : "\(label) Wiki"
    }

    private func metaBadges(_ page: Resources_Wiki_Page) -> [WikiBadge] {
        var badges: [WikiBadge] = []
        let meta = page.meta
        if meta.hasCreatedAt {
            badges.append(WikiBadge(title: "Erstellt \(formatTimestamp(meta.createdAt))", icon: "calendar"))
        }
        if meta.hasUpdatedAt {
            badges.append(WikiBadge(title: "Aktualisiert \(formatTimestamp(meta.updatedAt))", icon: "calendar.badge.plus"))
        }
        if meta.hasDeletedAt {
            badges.append(WikiBadge(title: "Gelöscht \(formatTimestamp(meta.deletedAt))", icon: "trash"))
        }
        if meta.draft {
            badges.append(WikiBadge(title: "Entwurf", icon: "pencil"))
        }
        if meta.startpage {
            badges.append(WikiBadge(title: "Startseite", icon: "house"))
        }
        if meta.public {
            badges.append(WikiBadge(title: "Öffentlich", icon: "globe"))
        }
        return badges
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await appState.getWikiPage(id: pageID)
            page = loaded
            let response = try await appState.listWikiPages(job: loaded.job, rootOnly: false, pageSize: 500)
            tree = response.pages
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the set of page ids that are ancestors of the given page.
    private static func ancestorIDs(of id: Int64, in pages: [Resources_Wiki_PageShort]) -> Set<Int64> {
        var result = Set<Int64>()
        func walk(_ nodes: [Resources_Wiki_PageShort], ancestors: [Int64]) {
            for node in nodes {
                if node.id == id {
                    result = Set(ancestors)
                    return
                }
                walk(node.children, ancestors: ancestors + [node.id])
            }
        }
        walk(pages, ancestors: [])
        return result
    }
}

private struct WikiBadge: Hashable {
    let title: String
    let icon: String
}

private struct WikiTreeNodeView: View {
    let page: Resources_Wiki_PageShort
    let currentID: Int64
    let ancestors: Set<Int64>

    @State private var isExpanded: Bool

    init(page: Resources_Wiki_PageShort, currentID: Int64, ancestors: Set<Int64>) {
        self.page = page
        self.currentID = currentID
        self.ancestors = ancestors
        _isExpanded = State(initialValue: ancestors.contains(page.id) || page.id == currentID)
    }

    private var isActive: Bool { page.id == currentID }
    private var hasChildren: Bool { !page.children.isEmpty }

    var body: some View {
        if hasChildren {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            nodeLabel
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    NavigationLink(value: page.id) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, Theme.Spacing.xs)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(page.children) { child in
                            WikiTreeNodeView(page: child, currentID: currentID, ancestors: ancestors)
                        }
                    }
                    .padding(.leading, Theme.Spacing.xl)
                }
            }
        } else {
            NavigationLink(value: page.id) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    nodeLabel
                }
            }
        }
    }

    private var nodeLabel: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(page.title.isEmpty ? "Unbenannt" : page.title)
                .font(.subheadline)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
            if isActive {
                Circle()
                    .fill(Theme.Palette.info)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// Simple horizontal wrapping layout for badge rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + (rowWidth == 0 ? 0 : spacing) > width {
                height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                if rowWidth != 0 { rowWidth += spacing }
                rowWidth += size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

import Foundation
import Observation
import SwiftProtobuf

/// A single entry of the centrum activity feed, derived from the live
/// `unitStatus` / `dispatchStatus` stream events.
struct CentrumActivityEntry: Identifiable, Equatable {
    let id: Int64
    let timestamp: Resources_Timestamp_Timestamp
    let icon: String
    let title: String
    let subtitle: String

    init(unitStatus status: Resources_Centrum_Units_UnitStatus, unit: Resources_Centrum_Units_Unit? = nil) {
        id = status.id
        timestamp = status.createdAt
        icon = status.feedIcon
        let unitName = (unit ?? status.unit).name
        title = unitName.isEmpty ? "Einheit #\(status.unitID)" : unitName
        subtitle = Self.subtitle(status: status.feedLabel, reason: status.reason, code: status.code, user: status.user)
    }

    init(dispatchStatus status: Resources_Centrum_Dispatches_DispatchStatus) {
        id = status.id
        timestamp = status.createdAt
        icon = status.feedIcon
        title = formatDispatchID(status.dispatchID)
        subtitle = Self.subtitle(status: status.feedLabel, reason: status.reason, code: status.code, user: status.user)
    }

    private static func subtitle(status: String, reason: String, code: String, user: Resources_Jobs_Colleagues_Colleague) -> String {
        var parts: [String] = [status]
        if !code.isEmpty { parts.append("Code \(code)") }
        if !reason.isEmpty { parts.append(reason) }
        parts.append("von \(colleagueName(user))")
        return parts.joined(separator: " · ")
    }
}

/// A fullscreen dispatch alarm shown when the character's own unit is assigned
/// to a dispatch. Carries the dispatch snapshot for the overlay UI.
struct DispatchAlarm: Identifiable {
    /// The kind of the alarm: a regular new assignment (red) or a
    /// reinforcement request (yellow, `needAssistance`).
    enum Kind {
        case assignment
        case reinforcement
    }

    let id: Int64
    let dispatch: Resources_Centrum_Dispatches_Dispatch
    let kind: Kind
    /// The colleague who triggered the alarm (e.g. the requesting unit for a
    /// reinforcement). Falls back to the dispatch creator when unavailable.
    let requester: Resources_Jobs_Colleagues_Colleague?

    init(id: Int64, dispatch: Resources_Centrum_Dispatches_Dispatch, kind: Kind = .assignment, requester: Resources_Jobs_Colleagues_Colleague? = nil) {
        self.id = id
        self.dispatch = dispatch
        self.kind = kind
        self.requester = requester
    }
}

/// Central application coordinator: drives the auth flow, owns the network client
/// and the resolved character session.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case setupServer
        case serverPicker
        case login
        case chooseCharacter
        case overview
    }

    enum Busy: Equatable {
        case none
        case login
        case choosingCharacter
        case connecting
    }

    let session: AuthSessionStore

    private(set) var phase: Phase = .setupServer
    private(set) var client: FiveNetClient?
    private(set) var characters: [Resources_Accounts_Character] = []
    private(set) var character: Resources_Users_User?
    private(set) var busy: Busy = .none
    private(set) var isChannelConnected = false
    private(set) var errorMessage: String?

    /// The active character's job properties (logo, radio frequency, MOTD) as
    /// delivered by the auth `ChooseCharacter` response. The server `GetJobProps`
    /// RPC is permission-gated, so web and the app use the auth response instead.
    private(set) var jobProps: Resources_Jobs_Props_JobProps?
    /// Permissions granted to the active character's job grade (guardName slugs).
    private(set) var permissions: [Resources_Permissions_Permissions_Permission] = []
    /// Role attributes granted to the active character (for `attr` checks).
    private(set) var attributes: [Resources_Permissions_Attributes_RoleAttribute] = []

    /// Persisted id of the last selected character, so the full user can be
    /// re-fetched when a session is restored from storage. Stored per server so
    /// switching servers does not mix up character ids (the demo server uses
    /// different ids than a production server).
    private var characterUserID: Int32? {
        get {
            guard let serverURL = session.serverURL else { return nil }
            return UserDefaults.standard.object(forKey: Self.characterUserIDKey(for: serverURL)) as? Int32
                ?? UserDefaults.standard.object(forKey: "selectedCharacterID") as? Int32
        }
        set {
            guard let serverURL = session.serverURL else { return }
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.characterUserIDKey(for: serverURL))
            } else {
                UserDefaults.standard.removeObject(forKey: Self.characterUserIDKey(for: serverURL))
            }
        }
    }

    private static func characterUserIDKey(for url: URL) -> String {
        "selectedCharacterID#\(url.absoluteString)"
    }

    /// Persisted id of the unit the user wants to be placed into when taking
    /// over the Leitstelle ("Übernehmen"-Tab). Stored per server. Observable so
    /// the "Leitstellen-Einheit verlassen" toolbar button updates reactively.
    var dutyUnitID: Int64? {
        willSet {
            guard let serverURL = session.serverURL else { return }
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.dutyUnitIDKey(for: serverURL))
            } else {
                UserDefaults.standard.removeObject(forKey: Self.dutyUnitIDKey(for: serverURL))
            }
        }
    }

    private static func dutyUnitIDKey(for url: URL) -> String {
        "dutyUnitID#\(url.absoluteString)"
    }

    /// Reloads the persisted duty-unit choice of the currently active server.
    private func loadDutyUnitID() {
        guard let serverURL = session.serverURL else {
            dutyUnitID = nil
            return
        }
        dutyUnitID = UserDefaults.standard.object(forKey: Self.dutyUnitIDKey(for: serverURL)) as? Int64
    }

    /// Persists the unit the user is placed into when taking over the Leitstelle.
    func setDutyUnit(_ unitID: Int64?) {
        dutyUnitID = unitID
    }

    /// Currently selected Leitstellen-Einheit (see `setDutyUnit`).
    var selectedDutyUnitID: Int64? {
        dutyUnitID
    }

    /// The persisted selected character id, regardless of whether the full
    /// character object has been loaded. Falls back to the loaded character.
    var activeCharacterUserID: Int32? {
        character?.userID ?? characterUserID
    }

    init(session: AuthSessionStore? = nil) {
        self.session = session ?? AuthSessionStore()
        favoriteUnitIDs = Set((UserDefaults.standard.array(forKey: "favoriteUnitIDs") as? [Int64]) ?? [])
        pinnedWikiJobs = (UserDefaults.standard.array(forKey: "pinnedWikiJobs") as? [String]) ?? []
        loadDutyUnitID()
        loadClosedDispatchIDs()
        if let serverURL = self.session.serverURL {
            makeClient(baseURL: serverURL)
        }
        restore()
    }

    // MARK: - Session restoration

    func restore() {
        guard let serverURL = session.serverURL else {
            phase = session.servers.isEmpty ? .setupServer : .serverPicker
            return
        }
        makeClient(baseURL: serverURL)
        if session.userToken != nil {
            if characterUserID != nil {
                phase = .overview
                Task {
                    await connectChannel()
                    await restoreCharacter()
                }
            } else {
                // A user token exists but no character id was persisted (e.g. a
                // character switch was interrupted). The account token is still
                // valid, so recover through the character picker instead of
                // showing an overview stuck on the skeleton grid.
                if session.accountToken != nil {
                    phase = .chooseCharacter
                    Task { await loadCharacters() }
                } else {
                    phase = .login
                }
            }
        } else if session.accountToken != nil {
            phase = .chooseCharacter
            Task { await loadCharacters() }
        } else {
            phase = .login
        }
    }

    // MARK: - Server setup

    func submitServerURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.normalizedURL(trimmed) else {
            errorMessage = "Bitte gib eine gültige Server-Adresse an."
            return
        }
        errorMessage = nil
        session.setServerURL(url)
        makeClient(baseURL: url)
        enterSelectedServer()
    }

    func selectServer(_ url: URL) {
        errorMessage = nil
        session.activate(url)
        makeClient(baseURL: url)
        enterSelectedServer()
    }

    func addServer() {
        errorMessage = nil
        phase = .setupServer
    }

    func removeServer(_ url: URL) {
        session.removeServer(url)
        if session.activeServer == nil {
            client = nil
            resetSessionData()
            phase = session.servers.isEmpty ? .setupServer : .serverPicker
        } else if let active = session.activeServer {
            makeClient(baseURL: active)
            enterSelectedServer()
        }
    }

    func changeServer() {
        errorMessage = nil
        phase = .serverPicker
    }

    /// Returns to the character-selection list without logging out: keeps the
    /// account token, resets the character-bound state and reloads the list.
    /// The persisted per-server character id is dropped so a relaunch does not
    /// auto-restore the character the user just switched away from.
    func switchCharacter() {
        errorMessage = nil
        resetSessionData()
        loadClosedDispatchIDs()
        characterUserID = nil
        Task { await loadCharacters() }
    }

    func doneChangingServer() {
        guard let active = session.activeServer else {
            client = nil
            resetSessionData()
            phase = .setupServer
            return
        }
        makeClient(baseURL: active)
        enterSelectedServer()
    }

    /// Enters the newly activated server and forces a fresh character selection
    /// so a character of another server can never leak into this session.
    private func enterSelectedServer() {
        loadDutyUnitID()
        resetSessionData()
        loadClosedDispatchIDs()
        if session.accountToken != nil || session.userToken != nil {
            phase = .chooseCharacter
            Task { await loadCharacters() }
        } else {
            phase = .login
        }
    }

    /// Resets all character-bound in-memory state: channel, streams and lists,
    /// so no data of a previously active server/character leaks into the next
    /// session. The persisted per-server character id is kept for relaunch
    /// auto-restore.
    private func resetSessionData() {
        stopCentrumStream()
        stopLivemapStream()
        client?.disconnectChannel()
        isChannelConnected = false
        isCentrumStreamActive = false
        isLivemapStreamActive = false
        character = nil
        jobProps = nil
        permissions = []
        attributes = []
        isDispatcher = false
        busy = .none
        dispatches = []
        units = []
        ownUnitID = nil
        centrumDispatchers = []
        closedDispatchIDs = []
        activeAlarm = nil
        alarmedDispatchIDs = []
        acceptedDispatchIDs = []
        livemapMarkers = []
        livemapMarkerMarkers = []
    }

    private static func normalizedURL(_ input: String) -> URL? {
        var candidate = input
        if !candidate.lowercased().hasPrefix("http://") && !candidate.lowercased().hasPrefix("https://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        if candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        return URL(string: candidate)
    }

    private func makeClient(baseURL: URL) {
        // Tear down the previous client's channel first: `self.client` is
        // replaced below, so `resetSessionData`'s `disconnectChannel` call would
        // otherwise target the freshly created (never-connected) client and the
        // old WebSocket would keep running + auto-reconnecting against the old
        // server (visible as TCP-RST frames in the console).
        client?.disconnectChannel()
        let client = FiveNetClient(baseURL: baseURL)
        client.setAuthTokens(accountToken: session.accountToken, userToken: session.userToken)
        client.setChannelStatusHandler { [weak self] connected in
            Task { @MainActor [weak self] in
                self?.isChannelConnected = connected
            }
        }
        self.client = client
    }

    // MARK: - Auth flow

    func login(username: String, password: String) async {
        guard let client else { return }
        busy = .login
        errorMessage = nil
        do {
            try await client.login(username: username, password: password)
            session.setUsername(username)
            session.update(accountToken: client.accountToken)
            await loadCharacters()
        } catch {
            errorMessage = Self.describe(error)
            busy = .none
        }
    }

    func loadCharacters() async {
        guard let client else { return }
        busy = .login
        errorMessage = nil
        do {
            characters = try await client.getCharacters()
            busy = .none
            if characters.isEmpty {
                throw FiveNetError.loginFailed("Für dieses Konto sind keine Charaktere verfügbar.")
            }
            phase = .chooseCharacter
        } catch {
            errorMessage = Self.describe(error)
            busy = .none
        }
    }

    func chooseCharacter(id: Int32) async {
        guard let client else { return }
        busy = .choosingCharacter
        errorMessage = nil
        do {
            let response = try await client.chooseCharacter(id: id)
            session.update(userToken: client.userToken)
            character = response.char
            characterUserID = id
            jobProps = response.hasJobProps ? response.jobProps : nil
            permissions = response.permissions
            attributes = response.attributes
            busy = .none
            phase = .overview
            Task { await connectChannel() }
        } catch {
            errorMessage = Self.describe(error)
            busy = .none
        }
    }

    func connectChannel() async {
        guard let client else { return }
        busy = .connecting
        do {
            try await client.connectChannel()
            busy = .none
        } catch {
            busy = .none
            errorMessage = Self.describe(error)
        }
    }

    /// Re-fetches the current character after a session restore, so fields like
    /// the character id are available even though `chooseCharacter` was skipped.
    /// Mirrors the web restore flow: `chooseCharacter` is re-run to also refresh
    /// the session's job properties, permissions and attributes, falling back to
    /// a plain citizen fetch when the character token is no longer accepted.
    private func restoreCharacter() async {
        guard let client, character == nil, let userID = characterUserID else { return }
        do {
            let response = try await client.chooseCharacter(id: userID)
            session.update(userToken: client.userToken)
            character = response.char
            jobProps = response.hasJobProps ? response.jobProps : nil
            permissions = response.permissions
            attributes = response.attributes
        } catch {
            if let char = try? await client.getCitizen(userID: userID) {
                character = char
            } else {
                errorMessage = Self.describe(error)
                // The stored character can no longer be resolved (e.g. it was
                // locked, deleted or belongs to a different server). Recover via
                // the character picker so the user is not stuck on an empty
                // overview skeleton grid.
                if let chars = try? await client.getCharacters(), !chars.isEmpty {
                    characters = chars
                    phase = .chooseCharacter
                }
            }
        }
    }

    /// Ensures the full `character` object is loaded (blocking if needed), so
    /// callers that send the character to the server always send a complete user.
    /// Returns the active character id, or nil if nothing is loaded.
    @discardableResult
    func ensureCharacterLoaded() async -> Int32? {
        if character == nil, let userID = characterUserID {
            if let client {
                if let char = try? await client.getCitizen(userID: userID) {
                    character = char
                }
            }
        }
        return character?.userID
    }

    // MARK: - Permissions

    private static let jobAdminPermGuard = "internal-superuser-jobadmin"
    private static let configAdminPermGuard = "internal-superuser-configadmin"
    private static let superuserCanBePermGuard = "internal-superuser-canbesuperuser"

    /// True when the active character is in superuser (job admin) mode, mirroring
    /// the web `isSuperuser` computed property.
    var isSuperuser: Bool {
        permissions.contains { $0.guardName == Self.jobAdminPermGuard }
    }

    /// Replicates the web `toGuardName`: `slug(perm.replaceAll('/', '.'))` with
    /// slugify's dot→dash replacement. The server stores `guardName` values built
    /// with the same `slug.Make` logic.
    static func guardName(for permission: String) -> String {
        slugify(permission.replacingOccurrences(of: "/", with: "."))
    }

    /// Permission check mirroring the web `canOne`: an explicit superuser guard
    /// bypass, then a plain guard-name lookup, with a superuser short-circuit.
    func can(_ permission: String) -> Bool {
        let guardName = Self.guardName(for: permission)
        if guardName == Self.jobAdminPermGuard { return isSuperuser }
        if guardName == Self.configAdminPermGuard { return canBeConfigAdmin }
        if guardName == Self.superuserCanBePermGuard { return canBeSuperuser }
        if isSuperuser { return true }
        return permissions.contains { $0.guardName == guardName }
    }

    /// True when the account can access config-admin gated screens and RPCs
    /// (web `canBeConfigAdmin`). The server delivers `PermConfigAdmin`
    /// (`internal-superuser-configadmin`) in the character permission list when
    /// the account is config-admin eligible (auth.go), mirroring `isSuperuser`.
    var canBeConfigAdmin: Bool {
        permissions.contains { $0.guardName == Self.configAdminPermGuard }
    }

    /// True when the account is allowed to switch into superuser mode. Without a
    /// dedicated RPC in the app, this is only true while superuser is active.
    var canBeSuperuser: Bool {
        isSuperuser
    }

    /// Simplified slugify matching `gosimple/slug`/`slugify` for guard names:
    /// lowercase, every run of non-alphanumerics becomes a single `-`.
    static func slugify(_ input: String) -> String {
        let lower = input.lowercased()
        var result = ""
        var pendingDash = false
        for scalar in lower.unicodeScalars {
            let isAlnum = CharacterSet.alphanumerics.contains(scalar)
            if isAlnum {
                if pendingDash && !result.isEmpty {
                    result.append("-")
                }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return result
    }

    func logout() async {
        if let client {
            client.disconnectChannel()
            try? await client.logout()
        }
        client?.resetAuth()
        session.clearSession()
        characters = []
        character = nil
        characterUserID = nil
        jobProps = nil
        permissions = []
        attributes = []
        errorMessage = nil
        phase = .login
    }

    // MARK: - Module access

    /// Modules shown on the overview. Every module is gated by the delivered
    /// permissions: a character without any permission inside that service
    /// namespace does not see the module (otherwise the module would only error
    /// with `ErrPermissionDenied`). Superuser and an empty permission list
    /// (e.g. servers that deliver none) show everything. The calendar is exempt:
    /// access can be granted implicitly (e.g. via job-calendar membership)
    /// without a `calendar`-namespace permission being delivered.
    var accessibleModules: [FiveNetModule] {
        guard !permissions.isEmpty else { return FiveNetModule.allCases }
        if isSuperuser { return FiveNetModule.allCases }
        return FiveNetModule.allCases.filter { module in
            module == .calendar || hasAccess(to: module)
        }
    }

    /// Whether the character holds at least one permission inside the module's
    /// service namespace. The delivered `namespace` field is authoritative; the
    /// guardName prefix check is a fallback for servers that only send slugs.
    private func hasAccess(to module: FiveNetModule) -> Bool {
        let prefix = "services-\(module.rawValue)-"
        return permissions.contains { perm in
            perm.namespace == module.rawValue || perm.guardName.hasPrefix(prefix)
        }
    }

    // MARK: - Citizens data

    func listCitizens(search: String, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Citizens_ListCitizensResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listCitizens(search: search, offset: offset, pageSize: pageSize)
    }

    func getCitizen(userID: Int32) async throws -> Resources_Users_User {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getCitizen(userID: userID)
    }

    func listUserActivity(userID: Int32, offset: Int64 = 0, pageSize: Int64 = 100) async throws -> Services_Citizens_ListUserActivityResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listUserActivity(userID: userID, offset: offset, pageSize: pageSize)
    }

    // MARK: - Vehicles data

    func listVehicles(licensePlate: String = "", model: String = "", userIds: [Int32] = [], offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Vehicles_ListVehiclesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listVehicles(licensePlate: licensePlate, model: model, userIds: userIds, offset: offset, pageSize: pageSize)
    }

    func completeCitizens(search: String, userIds: [Int32] = []) async throws -> [Resources_Users_Short_UserShort] {
        guard let client else { throw FiveNetError.notConnected }
        let response = try await client.completeCitizens(search: search, userIds: userIds)
        return response.users
    }

    func listVehicleActivity(plate: String, offset: Int64 = 0, pageSize: Int64 = 100) async throws -> Services_Vehicles_ListVehicleActivityResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listVehicleActivity(plate: plate, offset: offset, pageSize: pageSize)
    }

    // MARK: - Centrum data

    private(set) var dispatches: [Resources_Centrum_Dispatches_Dispatch] = []
    private(set) var units: [Resources_Centrum_Units_Unit] = []
    private(set) var centrumActivity: [CentrumActivityEntry] = []
    private(set) var isCentrumStreamActive = false
    private(set) var centrumError: String?

    /// The id of the current character's own unit (from the centrum stream).
    private(set) var ownUnitID: Int64?

    /// The currently displayed dispatch alarm, if any. Shown as a fullscreen
    /// overlay when the character's own unit is assigned to a dispatch.
    private(set) var activeAlarm: DispatchAlarm?

    /// Dispatch ids that already triggered an alarm this session, so a replayed
    /// `unitAssigned` status event does not fire the alarm twice.
    private var alarmedDispatchIDs: Set<Int64> = []

    /// Whether the current character is signed on as a centrum dispatcher.
    private(set) var isDispatcher = false

    /// Dispatcher lists per job (accumulated from the centrum stream).
    private(set) var centrumDispatchers: [Resources_Centrum_Dispatchers_Dispatchers] = []

    /// The job the current character is signed on as a dispatcher for.
    var dispatcherJob: String? {
        guard let userID = character?.userID else { return nil }
        return centrumDispatchers.first { job in
            job.dispatchers.contains { $0.userID == userID }
        }?.job
    }

    /// The current character's own unit, if any.
    var ownUnit: Resources_Centrum_Units_Unit? {
        guard let ownUnitID else { return nil }
        return units.first { $0.id == ownUnitID }
    }

    // MARK: - Unit favorites (persisted, observable)

    /// Persisted unit favorites. Stored (not computed) so the units tab
    /// re-renders when a favorite is toggled.
    var favoriteUnitIDs: Set<Int64> = []

    func toggleUnitFavorite(_ unitID: Int64) {
        if favoriteUnitIDs.contains(unitID) {
            favoriteUnitIDs.remove(unitID)
        } else {
            favoriteUnitIDs.insert(unitID)
        }
        UserDefaults.standard.set(Array(favoriteUnitIDs), forKey: "favoriteUnitIDs")
    }

    // MARK: - Wiki pins (persisted, observable)

    /// Job ids of pinned wikis (root pages). Stored so the UI re-renders.
    var pinnedWikiJobs: [String] = []

    func toggleWikiPin(_ job: String) {
        if pinnedWikiJobs.contains(job) {
            pinnedWikiJobs.removeAll { $0 == job }
        } else {
            pinnedWikiJobs.append(job)
        }
        UserDefaults.standard.set(pinnedWikiJobs, forKey: "pinnedWikiJobs")
    }

    func isWikiPinned(_ job: String) -> Bool {
        pinnedWikiJobs.contains(job)
    }

    func clearCentrumError() {
        centrumError = nil
    }

    private var centrumStreamTask: Task<Void, Never>?
    private var centrumRestartTask: Task<Void, Never>?
    private var livemapStreamTask: Task<Void, Never>?
    private var livemapRestartTask: Task<Void, Never>?

    /// Ensures the multiplexed channel is connected before issuing calls. Guards
    /// against reconnecting while the channel is already up (which would tear
    /// down running streams).
    private func ensureChannel() async throws {
        guard let client else { throw FiveNetError.notConnected }
        if !client.isChannelConnected {
            try await client.connectChannel()
        }
    }

    func loadDispatches() async {
        guard let client else { return }
        centrumError = nil
        do {
            try await ensureChannel()
            let response = try await client.listDispatches()
            dispatches = activeDispatches(response.dispatches)
            // Resolve ambiguous `.unitUnassigned` dispatches in the background so
            // the list renders immediately; known-closed ids are already filtered
            // from the persisted per-server set (no network round-trips on relaunch).
            let candidates = response.dispatches
            Task { [weak self] in
                await self?.verifyUnitUnassignedDispatches(candidates)
            }
        } catch {
            if !Self.isTransientConnectionError(error) {
                centrumError = Self.describe(error)
            }
        }
    }

    func createDispatch(job: String, message: String, description: String = "", anon: Bool = false, x: Double = 0, y: Double = 0, postal: String = "") async throws -> Resources_Centrum_Dispatches_Dispatch {
        guard let client else { throw FiveNetError.notConnected }
        try await ensureChannel()
        let dispatch = try await client.createDispatch(job: job, message: message, description: description, anon: anon, x: x, y: y, postal: postal)
        await loadDispatches()
        return dispatch
    }

    /// Searches dispatches by id, postal code and creator (used by global search).
    func searchDispatches(ids: [Int64] = [], postal: String = "", creatorIds: [Int32] = [], status: [Resources_Centrum_Dispatches_StatusDispatch] = [], offset: Int64 = 0, pageSize: Int64 = 100) async throws -> Services_Centrum_ListDispatchesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.searchDispatches(ids: ids, postal: postal, creatorIds: creatorIds, status: status, offset: offset, pageSize: pageSize)
    }

    /// Fetches the dispatch heatmap overlay (weighted dispatch hotspots).
    func getDispatchHeatmap() async throws -> Services_Centrum_GetDispatchHeatmapResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getDispatchHeatmap()
    }

    /// Statuses that are considered "closed" and are hidden from the live
    /// Leitstelle list and the livemap.
    private static let closedDispatchStatuses: Set<Resources_Centrum_Dispatches_StatusDispatch> = [
        .completed, .cancelled, .archived, .deleted,
    ]

    /// Dispatch ids that are considered closed. Persisted per server so a
    /// relaunch filters known-closed dispatches instantly (no network call):
    /// the server appends a `UNIT_UNASSIGNED` status row whenever a unit is
    /// removed - even from a completed dispatch - so `ListDispatches` (latest DB
    /// status) would otherwise revive a closed dispatch as `.unitUnassigned`.
    private(set) var closedDispatchIDs: Set<Int64> = []

    /// Dispatch ids whose activity feed was already checked this session, to
    /// avoid refetching the activity for the same dispatch on every refresh.
    private var verifiedClosedDispatchIDs: Set<Int64> = []

    private static func closedDispatchIDsKey(for url: URL) -> String {
        "closedDispatchIDs#\(url.absoluteString)"
    }

    /// Restores the persisted closed dispatch ids of the currently active server.
    private func loadClosedDispatchIDs() {
        guard let serverURL = session.serverURL else {
            closedDispatchIDs = []
            return
        }
        closedDispatchIDs = Set((UserDefaults.standard.array(forKey: Self.closedDispatchIDsKey(for: serverURL)) as? [Int64]) ?? [])
    }

    /// Persists the closed dispatch ids for the currently active server.
    private func persistClosedDispatchIDs() {
        guard let serverURL = session.serverURL else { return }
        UserDefaults.standard.set(Array(closedDispatchIDs), forKey: Self.closedDispatchIDsKey(for: serverURL))
    }

    /// Filters a list of dispatches down to the active (non-closed) ones.
    /// Dispatches that have ever been closed remain hidden.
    func activeDispatches(_ dispatches: [Resources_Centrum_Dispatches_Dispatch]) -> [Resources_Centrum_Dispatches_Dispatch] {
        var changed = false
        let filtered = dispatches.filter { dispatch in
            if Self.closedDispatchStatuses.contains(dispatch.status.status) {
                changed = closedDispatchIDs.insert(dispatch.id).inserted || changed
                return false
            }
            return !closedDispatchIDs.contains(dispatch.id)
        }
        if changed { persistClosedDispatchIDs() }
        return filtered
    }

    /// Checks the activity feed of dispatches whose latest status is ambiguous
    /// (`.unitUnassigned`) against the closed statuses. The server appends a
    /// `UNIT_UNASSIGNED` row when a unit is removed from a dispatch - even from a
    /// completed one - so the latest status alone is not reliable. If the activity
    /// history ever reached a closed status, the dispatch stays hidden.
    func verifyUnitUnassignedDispatches(_ dispatches: [Resources_Centrum_Dispatches_Dispatch]) async {
        guard let client else { return }
        let candidates = dispatches.filter {
            $0.status.status == .unitUnassigned
                && !closedDispatchIDs.contains($0.id)
                && !verifiedClosedDispatchIDs.contains($0.id)
        }
        guard !candidates.isEmpty else { return }
        candidates.forEach { verifiedClosedDispatchIDs.insert($0.id) }

        // The gRPC-Web channel supports max 7 concurrent streams; the centrum/
        // livemap streams already occupy slots. Cloudflare-protected servers
        // throttle bursts of concurrent HTTP/2/3 requests, so keep the parallel
        // activity fetches low to avoid `nw_protocol` churn and slow/blocked loads.
        let maxConcurrent = 3
        var results: [Int64: Bool] = [:]
        await withTaskGroup(of: (Int64, Bool).self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<maxConcurrent {
                if let next = iterator.next() {
                    group.addTask { await Self.fetchClosedFlag(for: next.id, client: client) }
                }
            }
            while let (id, isClosed) = await group.next() {
                results[id] = isClosed
                if let next = iterator.next() {
                    group.addTask { await Self.fetchClosedFlag(for: next.id, client: client) }
                }
            }
        }

        for (id, isClosed) in results where isClosed {
            closedDispatchIDs.insert(id)
            self.dispatches.removeAll { $0.id == id }
        }
        persistClosedDispatchIDs()
    }

    private static func fetchClosedFlag(for id: Int64, client: FiveNetClient) async -> (Int64, Bool) {
        do {
            let activity = try await client.listDispatchActivity(dispatchID: id, pageSize: 100)
            return (id, activity.activity.contains(where: { Self.closedDispatchStatuses.contains($0.status) }))
        } catch {
            return (id, false)
        }
    }

    func loadUnits() async {
        guard let client else { return }
        centrumError = nil
        do {
            try await ensureChannel()
            let response = try await client.listUnits()
            units = response.units
        } catch {
            if !Self.isTransientConnectionError(error) {
                centrumError = Self.describe(error)
            }
        }
    }

    func loadCentrum() async {
        centrumError = nil
        async let d: Void = loadDispatches()
        async let u: Void = loadUnits()
        _ = await (d, u)
    }

    /// Starts the centrum live stream (server-streaming) and keeps the
    /// dispatch/unit state updated in real time. Restarts automatically (with
    /// backoff) when the stream ends or the websocket drops, so a transient
    /// interruption does not silently kill the live feed.
    func startCentrumStream() async {
        guard let client, centrumStreamTask == nil, !isCentrumStreamActive else { return }
        do {
            try await ensureChannel()
            let stream = try await client.centrumStream()
            isCentrumStreamActive = true
            centrumStreamTask = Task { [weak self] in
                do {
                    for try await response in stream {
                        self?.applyCentrumStream(response)
                    }
                    self?.isCentrumStreamActive = false
                    self?.centrumStreamTask = nil
                    guard !Task.isCancelled else { return }
                    self?.scheduleCentrumRestart(attempt: 1)
                } catch {
                    self?.isCentrumStreamActive = false
                    self?.centrumStreamTask = nil
                    guard !Task.isCancelled else { return }
                    if !Self.isTransientConnectionError(error) {
                        self?.centrumError = Self.describe(error)
                    }
                    self?.scheduleCentrumRestart(attempt: 1)
                }
            }
        } catch {
            if !Self.isTransientConnectionError(error) {
                centrumError = Self.describe(error)
            }
            scheduleCentrumRestart(attempt: 1)
        }
    }

    func stopCentrumStream() {
        centrumStreamTask?.cancel()
        centrumStreamTask = nil
        centrumRestartTask?.cancel()
        centrumRestartTask = nil
        isCentrumStreamActive = false
    }

    /// Restarts the centrum stream after an interruption. The restart itself
    /// re-invokes `startCentrumStream` (guarded against duplicates); the attempt
    /// counter drives an exponential backoff that resets on a successful open.
    /// While the channel is down, wait for its own auto-reconnect instead of
    /// forcing a new websocket connection from here.
    private func scheduleCentrumRestart(attempt: Int) {
        centrumRestartTask?.cancel()
        centrumRestartTask = Task { [weak self] in
            let delay = min(0.75 * pow(2, Double(attempt - 1)), 15)
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            guard self.isChannelConnected else {
                // The channel itself keeps reconnecting; only surface an error
                // once the backoff is exhausted so transient drops stay silent.
                if attempt >= 6 {
                    self.centrumError = FiveNetError.connectionClosed.localizedDescription
                }
                self.scheduleCentrumRestart(attempt: min(attempt + 1, 6))
                return
            }
            await self.startCentrumStream()
        }
    }

    private func applyCentrumStream(_ response: Services_Centrum_StreamResponse) {
        switch response.change {
        case .latestState(let state):
            units = state.units
            dispatches = activeDispatches(state.dispatches)
            ownUnitID = state.hasOwnUnitID ? state.ownUnitID : nil
            centrumDispatchers = state.dispatchers.dispatchers
            recomputeDispatcher()
            seedCentrumActivity(from: state)
            Task { [weak self] in
                await self?.verifyUnitUnassignedDispatches(state.dispatches)
            }
        case .unitUpdated(let unit):
            if let index = units.firstIndex(where: { $0.id == unit.id }) {
                units[index] = unit
            } else {
                units.append(unit)
            }
            syncOwnUnit(with: unit)
        case .unitDeleted(let id):
            units.removeAll { $0.id == id }
            if ownUnitID == id {
                ownUnitID = nil
            }
        case .dispatchUpdated(let dispatch):
            maybeTriggerAlarm(for: dispatch)
            dismissAlarmIfNoLongerMine(dispatch)
            if Self.closedDispatchStatuses.contains(dispatch.status.status) {
                closedDispatchIDs.insert(dispatch.id)
                alarmedDispatchIDs.remove(dispatch.id)
                acceptedDispatchIDs.remove(dispatch.id)
                dispatches.removeAll { $0.id == dispatch.id }
            } else if closedDispatchIDs.contains(dispatch.id) {
                dispatches.removeAll { $0.id == dispatch.id }
            } else if let index = dispatches.firstIndex(where: { $0.id == dispatch.id }) {
                dispatches[index] = dispatch
                if dispatch.status.status == .unitUnassigned {
                    Task { [weak self] in
                        await self?.verifyUnitUnassignedDispatches([dispatch])
                    }
                }
            } else {
                dispatches.append(dispatch)
            }
        case .dispatchDeleted(let id):
            dispatches.removeAll { $0.id == id }
        case .unitStatus(let status):
            insertCentrumActivity(CentrumActivityEntry(unitStatus: status))
        case .dispatchStatus(let status):
            insertCentrumActivity(CentrumActivityEntry(dispatchStatus: status))
            maybeTriggerAlarm(for: status)
            if status.status == .unitUnassigned {
                if alarmedDispatchIDs.remove(status.dispatchID) != nil, activeAlarm?.id == status.dispatchID {
                    activeAlarm = nil
                }
                acceptedDispatchIDs.remove(status.dispatchID)
            }
        case .handshake, .settings, .access, nil:
            break
        case .dispatchers(let jobDispatchers):
            if let index = centrumDispatchers.firstIndex(where: { $0.job == jobDispatchers.job }) {
                centrumDispatchers[index] = jobDispatchers
            } else {
                centrumDispatchers.append(jobDispatchers)
            }
            recomputeDispatcher()
        }
    }

    private func recomputeDispatcher() {
        guard let userID = character?.userID else {
            isDispatcher = false
            return
        }
        isDispatcher = centrumDispatchers.contains { job in
            job.dispatchers.contains { $0.userID == userID }
        }
    }

    /// Seeds the activity feed once from the current unit/dispatch statuses so
    /// the feed is not empty on first open.
    private func seedCentrumActivity(from state: Services_Centrum_LatestState) {
        guard centrumActivity.isEmpty else { return }
        var entries: [CentrumActivityEntry] = []
        for unit in state.units where unit.hasStatus {
            entries.append(CentrumActivityEntry(unitStatus: unit.status, unit: unit))
        }
        for dispatch in state.dispatches where dispatch.hasStatus {
            entries.append(CentrumActivityEntry(dispatchStatus: dispatch.status))
        }
        centrumActivity = Array(entries.sorted { $0.timestamp.timestamp.date > $1.timestamp.timestamp.date }.prefix(100))
    }

    private func insertCentrumActivity(_ entry: CentrumActivityEntry) {
        centrumActivity.insert(entry, at: 0)
        if centrumActivity.count > 100 {
            centrumActivity.removeLast(centrumActivity.count - 100)
        }
    }

    // MARK: - Dispatch alarm

    /// Fires the fullscreen alarm when a `UNIT_ASSIGNED` status targets the
    /// character's own unit. The status event carries the assigned unit id;
    /// the full dispatch snapshot is taken from the current dispatches list
    /// (fetched on demand when the update arrives before the dispatch itself).
    private func maybeTriggerAlarm(for status: Resources_Centrum_Dispatches_DispatchStatus) {
        guard let ownUnitID,
              status.unitID == ownUnitID,
              !acceptedDispatchIDs.contains(status.dispatchID),
              !alarmedDispatchIDs.contains(status.dispatchID) else { return }
        let kind: DispatchAlarm.Kind
        switch status.status {
        case .unitAssigned:
            kind = .assignment
        case .needAssistance:
            kind = .reinforcement
        default:
            return
        }
        // A reinforcement request raised by the current character must not fire
        // a panic for themselves — they already know they asked for help (the
        // blinking "Verstärkung" status button shows the state). Firing anyway
        // would hide the dispatch from "Dein Einsatz" via `pendingAlarmDispatchIDs`.
        if kind == .reinforcement, isOwnReinforcementRequest(status) {
            return
        }
        alarmedDispatchIDs.insert(status.dispatchID)
        let requester: Resources_Jobs_Colleagues_Colleague? = status.hasUser ? status.user : nil
        if let dispatch = dispatches.first(where: { $0.id == status.dispatchID }) {
            activeAlarm = DispatchAlarm(id: status.dispatchID, dispatch: dispatch, kind: kind, requester: requester)
        } else {
            Task { [weak self] in
                guard let self, let client = self.client else { return }
                if let dispatch = try? await client.getDispatch(id: status.dispatchID) {
                    self.activeAlarm = DispatchAlarm(id: status.dispatchID, dispatch: dispatch, kind: kind, requester: requester)
                } else {
                    self.alarmedDispatchIDs.remove(status.dispatchID)
                }
            }
        }
    }

    /// Robust fallback: some server builds broadcast assignments as an updated
    /// dispatch (latest status `UNIT_ASSIGNED`) instead of a separate
    /// `dispatch_status` event. Triggers the alarm when the assigned unit is
    /// the character's own.
    private func maybeTriggerAlarm(for dispatch: Resources_Centrum_Dispatches_Dispatch) {
        guard ownUnitID != nil,
              !acceptedDispatchIDs.contains(dispatch.id),
              !alarmedDispatchIDs.contains(dispatch.id),
              targetsOwnUnit(dispatch) else { return }
        let kind: DispatchAlarm.Kind
        switch dispatch.status.status {
        case .unitAssigned:
            kind = .assignment
        case .needAssistance:
            kind = .reinforcement
        default:
            return
        }
        if kind == .reinforcement, isOwnReinforcementRequest(dispatch.status) {
            return
        }
        alarmedDispatchIDs.insert(dispatch.id)
        activeAlarm = DispatchAlarm(id: dispatch.id, dispatch: dispatch, kind: kind, requester: dispatch.status.hasUser ? dispatch.status.user : nil)
    }

    /// Whether the reinforcement request on a `dispatch_status` event was raised
    /// by the current character themselves (checked via the requester user id).
    /// Such self-requests must not fire the reinforcement panic for the same
    /// character that pressed the button.
    private func isOwnReinforcementRequest(_ status: Resources_Centrum_Dispatches_DispatchStatus) -> Bool {
        guard let currentUserID = activeCharacterUserID else { return false }
        if status.hasUserID, status.userID == currentUserID { return true }
        if status.hasUser, status.user.userID == currentUserID { return true }
        return false
    }

    private func targetsOwnUnit(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> Bool {
        guard let ownUnitID else { return false }
        if dispatch.status.hasUnitID, dispatch.status.unitID == ownUnitID { return true }
        return dispatch.units.contains { $0.unitID == ownUnitID }
    }

    /// Dismisses the currently shown dispatch alarm (e.g. after accept/decline).
    func dismissAlarm() {
        activeAlarm = nil
    }

    /// Dispatches that triggered an alarm for the own unit but have not been
    /// accepted or withdrawn yet (the "pending" reminder state shown by the
    /// animated bell in the navigation bar).
    var pendingAlarmDispatchIDs: Set<Int64> {
        alarmedDispatchIDs
    }

    /// Dispatches the character's unit has explicitly accepted this session.
    /// Accepted dispatches never re-trigger the alarm until they are reassigned
    /// away again.
    private var acceptedDispatchIDs: Set<Int64> = []

    /// The dispatch currently needing the user's attention (alarm fired, not
    /// yet accepted and still assigned to the own unit).
    var pendingAlarmDispatch: Resources_Centrum_Dispatches_Dispatch? {
        guard !alarmedDispatchIDs.isEmpty else { return nil }
        return dispatches.first {
            alarmedDispatchIDs.contains($0.id)
                && targetsOwnUnit($0)
                && !Self.closedDispatchStatuses.contains($0.status.status)
        }
    }

    /// Re-opens the fullscreen alarm for the first still-pending dispatch
    /// (called from the bell in the navigation bar).
    func reopenPendingAlarm() {
        guard let dispatch = pendingAlarmDispatch else { return }
        activeAlarm = DispatchAlarm(id: dispatch.id, dispatch: dispatch)
    }

    // MARK: - Dispatch actions

    func updateDispatchStatus(_ dispatchID: Int64, status: Resources_Centrum_Dispatches_StatusDispatch, reason: String = "") async {
        guard let client else { return }
        centrumError = nil
        do {
            try await client.updateDispatchStatus(dispatchID: dispatchID, status: status, reason: reason)
            if Self.closedDispatchStatuses.contains(status) {
                closedDispatchIDs.insert(dispatchID)
                dispatches.removeAll { $0.id == dispatchID }
            } else if let index = dispatches.firstIndex(where: { $0.id == dispatchID }) {
                dispatches[index].status.status = status
            }
        } catch {
            centrumError = Self.describe(error)
        }
    }

    /// Signs the current character on as a centrum dispatcher ("Leitstelle übernehmen").
    /// If a duty unit was chosen in the Übernehmen-Tab, the character is joined
    /// into it automatically.
    func takeControl() async {
        guard let client else { return }
        centrumError = nil
        do {
            try await client.takeControl(signon: true)
            isDispatcher = true
            if let dutyUnitID {
                await joinUnit(dutyUnitID)
            }
            await loadCentrum()
        } catch {
            centrumError = Self.describe(error)
        }
    }

    /// Leaves the Leitstelle entirely: leaves the duty unit (if a duty unit was
    /// chosen), signs off as centrum dispatcher and clears the persisted
    /// duty-unit choice — so the "Übernehmen"-Tab returns and the leave visibly
    /// takes effect.
    func leaveDutyUnit() async {
        if let unitID = dutyUnitID {
            await leaveUnit(unitID)
        }
        setDutyUnit(nil)
        isDispatcher = false
        guard let client else { return }
        do {
            try await client.takeControl(signon: false)
            await loadCentrum()
        } catch {
            centrumError = Self.describe(error)
        }
    }

    func takeDispatch(_ id: Int64, resp: Resources_Centrum_Dispatches_TakeDispatchResp, reason: String = "") async {
        guard let client else { return }
        centrumError = nil
        do {
            try await client.takeDispatch(dispatchIds: [id], resp: resp, reason: reason)
            if resp == .accepted {
                acceptedDispatchIDs.insert(id)
            }
            alarmedDispatchIDs.remove(id)
            if activeAlarm?.id == id {
                activeAlarm = nil
            }
        } catch {
            centrumError = Self.describe(error)
        }
    }

    func assignDispatch(_ dispatchID: Int64, toAdd: [Int64], toRemove: [Int64]) async {
        guard let client else { return }
        centrumError = nil
        do {
            try await client.assignDispatch(dispatchID: dispatchID, toAdd: toAdd, toRemove: toRemove)
        } catch {
            centrumError = Self.describe(error)
        }
    }

    func updateUnitStatus(_ unitID: Int64, status: Resources_Centrum_Units_StatusUnit, reason: String = "") async {
        guard let client else { return }
        centrumError = nil
        do {
            try await client.updateUnitStatus(unitID: unitID, status: status, reason: reason)
            if let index = units.firstIndex(where: { $0.id == unitID }) {
                units[index].status.status = status
            }
        } catch {
            centrumError = Self.describe(error)
        }
    }

    func assignUnit(_ unitID: Int64, toAdd: [Int32], toRemove: [Int32]) async {
        guard let client else { return }
        centrumError = nil
        do {
            try await client.assignUnit(unitID: unitID, toAdd: toAdd, toRemove: toRemove)
            let userID = activeCharacterUserID
            if toRemove.contains(where: { $0 == userID }) {
                if ownUnitID == unitID {
                    ownUnitID = nil
                }
            } else if toAdd.contains(where: { $0 == userID }) {
                ownUnitID = unitID
            }
            await loadUnits()
        } catch {
            centrumError = Self.describe(error)
        }
    }

    /// Leaves the unit the current character is currently a member of.
    /// Removes the own character via `assignUnit` if available; otherwise it is
    /// a no-op with an error message (server-side the user must be assignable).
    func leaveUnit(_ unitID: Int64) async {
        guard let userID = activeCharacterUserID else {
            centrumError = "Du musst erst einen Charakter ausgewählt haben, um eine Einheit zu verlassen."
            return
        }
        await assignUnit(unitID, toAdd: [], toRemove: [userID])
    }

    /// Joins the current character into a unit ("Einheit beitreten").
    /// The server resolves the character from the auth token, no client-side userID needed.
    func joinUnit(_ unitID: Int64) async {
        guard let client else { return }
        centrumError = nil
        do {
            let unit = try await client.joinUnit(unitID: unitID)
            ownUnitID = unit.id
            if let index = units.firstIndex(where: { $0.id == unit.id }) {
                units[index] = unit
            } else {
                units.append(unit)
            }
        } catch {
            centrumError = Self.describe(error)
        }
    }

    /// Re-syncs `ownUnitID` after an incremental unit update broadcast from the
    /// server (the unit object carries its member list, so membership changes
    /// after join/leave/assign are reflected without waiting for a new latest state).
    private func syncOwnUnit(with unit: Resources_Centrum_Units_Unit) {
        guard let userID = activeCharacterUserID else {
            if ownUnitID == unit.id {
                ownUnitID = nil
            }
            return
        }
        let containsSelf = unit.users.contains { $0.userID == userID }
        if containsSelf {
            ownUnitID = unit.id
        } else if ownUnitID == unit.id {
            ownUnitID = nil
        }
    }

    /// Clears the alarm/pending state as soon as the dispatch is no longer
    /// assigned to the own unit (e.g. it was reassigned to another unit), also
    /// while the alarm was already closed via the X button (bell reminder).
    private func dismissAlarmIfNoLongerMine(_ dispatch: Resources_Centrum_Dispatches_Dispatch) {
        guard !targetsOwnUnit(dispatch) else { return }
        if alarmedDispatchIDs.remove(dispatch.id) != nil, activeAlarm?.id == dispatch.id {
            activeAlarm = nil
        }
        acceptedDispatchIDs.remove(dispatch.id)
    }

    // MARK: - Livemap data

    private(set) var livemapMarkers: [Resources_Livemap_Markers_UserMarker] = []
    private(set) var livemapMarkerMarkers: [Resources_Livemap_Markers_MarkerMarker] = []
    private(set) var isLivemapStreamActive = false
    private(set) var livemapError: String?

    /// Whether the active character is currently on duty ("im Dienst"), as
    /// reported by the livemap stream (`user_on_duty`). Used to gate unit join
    /// actions — the server rejects them with `ErrNotOnDuty` otherwise.
    private(set) var isOnDuty = false

    func clearLivemapError() {
        livemapError = nil
    }

    /// Starts the livemap stream and keeps the marker list updated. Restarts
    /// automatically after interruptions, mirroring the centrum stream.
    func startLivemapStream() async {
        guard let client, livemapStreamTask == nil, !isLivemapStreamActive else { return }
        do {
            try await ensureChannel()
            let stream = try await client.livemapStream()
            isLivemapStreamActive = true
            livemapStreamTask = Task { [weak self] in
                do {
                    for try await response in stream {
                        self?.applyLivemapStream(response)
                    }
                    self?.isLivemapStreamActive = false
                    self?.livemapStreamTask = nil
                    guard !Task.isCancelled else { return }
                    self?.scheduleLivemapRestart(attempt: 1)
                } catch {
                    self?.isLivemapStreamActive = false
                    self?.livemapStreamTask = nil
                    guard !Task.isCancelled else { return }
                    if !Self.isTransientConnectionError(error) {
                        self?.livemapError = Self.describe(error)
                    }
                    self?.scheduleLivemapRestart(attempt: 1)
                }
            }
        } catch {
            if !Self.isTransientConnectionError(error) {
                livemapError = Self.describe(error)
            }
            scheduleLivemapRestart(attempt: 1)
        }
    }

    func stopLivemapStream() {
        livemapStreamTask?.cancel()
        livemapStreamTask = nil
        livemapRestartTask?.cancel()
        livemapRestartTask = nil
        isLivemapStreamActive = false
    }

    private func scheduleLivemapRestart(attempt: Int) {
        livemapRestartTask?.cancel()
        livemapRestartTask = Task { [weak self] in
            let delay = min(0.75 * pow(2, Double(attempt - 1)), 15)
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            guard self.isChannelConnected else {
                // The channel itself keeps reconnecting; only surface an error
                // once the backoff is exhausted so transient drops stay silent.
                if attempt >= 6 {
                    self.livemapError = FiveNetError.connectionClosed.localizedDescription
                }
                self.scheduleLivemapRestart(attempt: min(attempt + 1, 6))
                return
            }
            await self.startLivemapStream()
        }
    }

    private func applyLivemapStream(_ response: Services_Livemap_StreamResponse) {
        if response.hasUserOnDuty {
            isOnDuty = response.userOnDuty
        }
        switch response.data {
        case .snapshot(let snapshot):
            livemapMarkers = snapshot.markers
        case .userUpdates(let updates):
            for marker in updates.updates {
                if let index = livemapMarkers.firstIndex(where: { $0.userID == marker.userID }) {
                    livemapMarkers[index] = marker
                } else {
                    livemapMarkers.append(marker)
                }
            }
        case .userDeletes(let deletes):
            for delete in deletes.deletes {
                livemapMarkers.removeAll { $0.userID == delete.id }
            }
        case .markers(let updates):
            var found: [Int64] = []
            for marker in updates.updated {
                if !updates.partial {
                    found.append(marker.id)
                }
                if let index = livemapMarkerMarkers.firstIndex(where: { $0.id == marker.id }) {
                    livemapMarkerMarkers[index] = marker
                } else {
                    livemapMarkerMarkers.append(marker)
                }
            }
            for id in updates.deleted {
                livemapMarkerMarkers.removeAll { $0.id == id }
            }
            if !updates.partial && updates.part <= 0 {
                livemapMarkerMarkers.removeAll { !found.contains($0.id) }
            }
        case .jobs, nil:
            break
        }
    }

    // MARK: - Wiki

    /// Lists wiki pages, optionally filtered by job, root pages only, and/or a search term.
    func listWikiPages(job: String = "", rootOnly: Bool = false, search: String = "", offset: Int64 = 0, pageSize: Int64 = 100) async throws -> Services_Wiki_ListPagesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listWikiPages(job: job, rootOnly: rootOnly, search: search, offset: offset, pageSize: pageSize)
    }

    /// Fetches a single wiki page including its content.
    func getWikiPage(id: Int64) async throws -> Resources_Wiki_Page {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getWikiPage(id: id)
    }

    // MARK: - Documents (Dokumente)

    /// Lists document categories.
    func listCategories() async throws -> Services_Documents_ListCategoriesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listCategories()
    }

    /// Lists documents with an optional search term, category filter, and closed state.
    func listDocuments(search: String = "", categoryIds: [Int64] = [], documentIds: [Int64] = [], closed: Bool? = nil, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Documents_ListDocumentsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listDocuments(search: search, categoryIds: categoryIds, documentIds: documentIds, closed: closed, offset: offset, pageSize: pageSize)
    }

    /// Fetches a single document including its content.
    func getDocument(id: Int64) async throws -> Resources_Documents_Document {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getDocument(id: id)
    }

    /// Lists pinned documents (optionally personal pins only).
    func listDocumentPins(personal: Bool = false, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Documents_ListDocumentPinsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listDocumentPins(personal: personal, offset: offset, pageSize: pageSize)
    }

    /// Pins or unpins a document for the current user / job.
    func toggleDocumentPin(documentID: Int64, state: Bool, personal: Bool = false) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.toggleDocumentPin(documentID: documentID, state: state, personal: personal)
    }

    /// Opens or closes a document.
    func toggleDocument(documentID: Int64, closed: Bool) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.toggleDocument(documentID: documentID, closed: closed)
    }

    /// Lists documents related to (or related from) the given document.
    func listDocumentRelations(documentID: Int64) async throws -> [Resources_Documents_Relations_DocumentRelation] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listDocumentRelations(documentID: documentID)
    }

    /// Lists documents referencing (or referenced by) the given document.
    func listDocumentReferences(documentID: Int64) async throws -> [Resources_Documents_References_DocumentReference] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listDocumentReferences(documentID: documentID)
    }

    /// Fetches the access configuration (jobs/users) of a document.
    func getDocumentAccess(documentID: Int64) async throws -> Resources_Access_Access {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getDocumentAccess(documentID: documentID)
    }

    /// Lists comments on a document.
    func listComments(documentID: Int64, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> [Resources_Documents_Comment_Comment] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listComments(documentID: documentID, offset: offset, pageSize: pageSize)
    }

    /// Lists document templates available for creating new documents.
    func listTemplates() async throws -> [Resources_Documents_Templates_TemplateShort] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listTemplates()
    }

    /// Creates a new document from a template and returns the new document id.
    /// When `templateID` is omitted, an empty document is created instead.
    func createDocument(templateID: Int64? = nil, templateData: Resources_Documents_Templates_TemplateData? = nil) async throws -> Int64 {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createDocument(templateID: templateID, templateData: templateData)
    }

    /// Fetches a template with rendered content for diagnostics (surfaces the raw
    /// template render error instead of the sanitized ErrFailedQuery).
    func getTemplate(templateID: Int64, templateData: Resources_Documents_Templates_TemplateData? = nil, render: Bool = false) async throws -> Resources_Documents_Templates_Template {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getTemplate(templateID: templateID, templateData: templateData, render: render)
    }

    /// Lists document relations for a given user (citizen "Dokumente" tab).
    func listUserDocuments(userID: Int32, closed: Bool? = nil, offset: Int64 = 0, pageSize: Int64 = 20) async throws -> [Resources_Documents_Relations_DocumentRelation] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listUserDocuments(userID: userID, closed: closed, offset: offset, pageSize: pageSize)
    }

    /// Updates a document (title, category, content, meta).
    func updateDocument(documentID: Int64, title: String, categoryID: Int64? = nil, content: Resources_Common_Content_Content, contentType: Resources_Common_Content_ContentType, data: Resources_Documents_Data_DocumentData? = nil, meta: Resources_Documents_DocumentMeta, access: Resources_Access_Access? = nil, files: [Resources_File_File] = []) async throws -> Resources_Documents_Document {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.updateDocument(documentID: documentID, title: title, categoryID: categoryID, content: content, contentType: contentType, data: data, meta: meta, access: access, files: files)
    }

    /// Soft-deletes a document (or restores it when already deleted).
    func deleteDocument(documentID: Int64, reason: String? = nil) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteDocument(documentID: documentID, reason: reason)
    }

    /// Takes ownership of a document (optionally assigning it to another user).
    func changeDocumentOwner(documentID: Int64, newUserID: Int32? = nil) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.changeDocumentOwner(documentID: documentID, newUserID: newUserID)
    }

    /// Sets or updates a personal reminder for a document.
    func setDocumentReminder(documentID: Int64, reminderTime: Resources_Timestamp_Timestamp? = nil, message: String? = nil, maxReminderCount: Int32 = 10) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.setDocumentReminder(documentID: documentID, reminderTime: reminderTime, message: message, maxReminderCount: maxReminderCount)
    }

    /// Lists document requests (Anfragen) for a document.
    func listDocumentReqs(documentID: Int64, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Documents_ListDocumentReqsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listDocumentReqs(documentID: documentID, offset: offset, pageSize: pageSize)
    }

    /// Creates a document request (e.g. requestedAccess, requestedClosure, …).
    func createDocumentReq(documentID: Int64, requestType: Resources_Documents_Activity_DocActivityType, reason: String) async throws -> Resources_Documents_Requests_DocRequest {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createDocumentReq(documentID: documentID, requestType: requestType, reason: reason)
    }

    /// Approves or declines a document request.
    func updateDocumentReq(documentID: Int64, requestID: Int64, accepted: Bool) async throws -> Resources_Documents_Requests_DocRequest {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.updateDocumentReq(documentID: documentID, requestID: requestID, accepted: accepted)
    }

    /// Deletes a document request.
    func deleteDocumentReq(requestID: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteDocumentReq(requestID: requestID)
    }

    /// Lists approval tasks for a document (optionally filtered by status).
    func listApprovalTasks(documentID: Int64, statuses: [Resources_Documents_Approval_ApprovalTaskStatus] = []) async throws -> [Resources_Documents_Approval_ApprovalTask] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listApprovalTasks(documentID: documentID, statuses: statuses)
    }

    /// Decides an approval task (approve or decline).
    func decideApproval(documentID: Int64, taskID: Int64, newStatus: Resources_Documents_Approval_ApprovalTaskStatus, comment: String = "") async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.decideApproval(documentID: documentID, taskID: taskID, newStatus: newStatus, comment: comment)
    }

    /// Fetches the approval policy (and document meta) of a document.
    func listApprovalPolicies(documentID: Int64) async throws -> Services_Documents_ListApprovalPoliciesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listApprovalPolicies(documentID: documentID)
    }

    // MARK: - Calendar

    /// Lists all calendars the active character can access.
    func listCalendars(offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Calendar_ListCalendarsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listCalendars(offset: offset, pageSize: pageSize)
    }

    /// Lists calendar entries for a specific month.
    func listCalendarEntries(year: Int32, month: Int32, calendarIds: [Int64] = []) async throws -> [Resources_Calendar_Entries_CalendarEntry] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listCalendarEntries(year: year, month: month, calendarIds: calendarIds)
    }

    /// Creates or updates a calendar entry in the given calendar.
    func createOrUpdateCalendarEntry(_ entry: Resources_Calendar_Entries_CalendarEntry, userIds: [Int32] = []) async throws -> Resources_Calendar_Entries_CalendarEntry {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createOrUpdateCalendarEntry(entry, userIds: userIds)
    }

    /// Deletes a calendar entry by id.
    func deleteCalendarEntry(id: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteCalendarEntry(id: id)
    }

    // MARK: - Jobs (Berufe)

    /// Fetches the job message of the day (MOTD).
    func getMOTD() async throws -> String {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getMOTD()
    }

    /// Sets the job message of the day (MOTD).
    func setMOTD(_ motd: String) async throws -> String {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.setMOTD(motd)
    }

    /// Lists colleagues with optional search, user-id, absence and label filters.
    func listColleagues(search: String = "", userIds: [Int32] = [], absent: Bool? = nil, labelIds: [Int64] = [], offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Jobs_ListColleaguesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listColleagues(search: search, userIds: userIds, absent: absent, labelIds: labelIds, offset: offset, pageSize: pageSize)
    }

    /// Fetches the current character's own colleague profile.
    func getSelfColleague() async throws -> Resources_Jobs_Colleagues_Colleague {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getSelfColleague()
    }

    /// Fetches a single colleague's full profile.
    func getColleague(userID: Int32) async throws -> Resources_Jobs_Colleagues_Colleague {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getColleague(userID: userID)
    }

    /// Lists colleague activity (Aktivität) filtered by user and activity types.
    func listColleagueActivity(userIds: [Int32] = [], activityTypes: [Resources_Jobs_Colleagues_Activity_ColleagueActivityType] = [], offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Jobs_ListColleagueActivityResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listColleagueActivity(userIds: userIds, activityTypes: activityTypes, offset: offset, pageSize: pageSize)
    }

    /// Sets colleague properties (absence, note, labels, name).
    func setColleagueProps(_ props: Resources_Jobs_Colleagues_ColleagueProps, reason: String = "") async throws -> Resources_Jobs_Colleagues_ColleagueProps {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.setColleagueProps(props, reason: reason)
    }

    /// Lists colleague labels, optionally filtered by search.
    func getColleagueLabels(search: String = "") async throws -> [Resources_Jobs_Labels_Label] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getColleagueLabels(search: search)
    }

    /// Creates/updates a single colleague label (v2026.8.1 RPC).
    func createOrUpdateLabel(_ label: Resources_Jobs_Labels_Label) async throws -> Resources_Jobs_Labels_Label {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createOrUpdateLabel(label)
    }

    /// Deletes a colleague label by id.
    func deleteLabel(id: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteLabel(id: id)
    }

    /// Reorders colleague labels by id (send the full ordered list of ids).
    func reorderLabels(_ labelIds: [Int64]) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.reorderLabels(labelIds)
    }

    /// Fetches label usage statistics (how many colleagues carry each label).
    func getColleagueLabelsStats(labelIds: [Int64] = []) async throws -> [Resources_Jobs_Labels_LabelCount] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getColleagueLabelsStats(labelIds: labelIds)
    }

    /// Lists timeclock entries (daily view).
    func listTimeclock(userMode: Resources_Jobs_Timeclock_TimeclockViewMode = .unspecified, mode: Resources_Jobs_Timeclock_TimeclockMode = .daily, perDay: Bool = false, userIds: [Int32] = [], start: Date? = nil, end: Date? = nil, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Jobs_ListTimeclockResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listTimeclock(userMode: userMode, mode: mode, perDay: perDay, userIds: userIds, start: start, end: end, offset: offset, pageSize: pageSize)
    }

    /// Fetches timeclock statistics for the current character (or a given user).
    func getTimeclockStats(userID: Int32? = nil) async throws -> Services_Jobs_GetTimeclockStatsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getTimeclockStats(userID: userID)
    }

    /// Lists inactive employees (no timeclock entry within the last `days` days).
    func listInactiveEmployees(days: Int32 = 30, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Jobs_ListInactiveEmployeesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listInactiveEmployees(days: days, offset: offset, pageSize: pageSize)
    }

    /// Lists conduct register entries.
    func listConductEntries(types: [Resources_Jobs_Conduct_ConductType] = [], userIds: [Int32] = [], showExpired: Bool? = nil, showDrafts: Bool? = nil, showDeleted: Bool? = nil, ids: [Int64] = [], offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Jobs_ListConductEntriesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listConductEntries(types: types, userIds: userIds, showExpired: showExpired, showDrafts: showDrafts, showDeleted: showDeleted, ids: ids, offset: offset, pageSize: pageSize)
    }

    /// Fetches a single conduct register entry by id.
    func getConductEntry(id: Int64) async throws -> Services_Jobs_GetConductEntryResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getConductEntry(id: id)
    }

    /// Creates a new conduct register entry.
    func createConductEntry(entry: Resources_Jobs_Conduct_ConductEntry) async throws -> Resources_Jobs_Conduct_ConductEntry {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createConductEntry(entry: entry)
    }

    /// Updates an existing conduct register entry.
    func updateConductEntry(entry: Resources_Jobs_Conduct_ConductEntry) async throws -> Resources_Jobs_Conduct_ConductEntry {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.updateConductEntry(entry: entry)
    }

    /// Fetches job props (logo, radio frequency, MOTD) for the current job.
    func getJobProps() async throws -> Resources_Jobs_Props_JobProps {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getJobProps()
    }

    /// Fetches fresh job props via `GetJobProps` and stores them (kept in sync
    /// with the auth-derived `jobProps`). Falls back to the auth payload when
    /// the endpoint is permission-gated.
    func reloadJobProps() async throws {
        guard let client else { throw FiveNetError.notConnected }
        let fresh = try await client.getJobProps()
        jobProps = fresh
    }

    /// Updates the active job's properties via `SetJobProps` and stores the
    /// server-returned props (kept in sync with the auth-derived `jobProps`).
    func setJobProps(_ props: Resources_Jobs_Props_JobProps) async throws -> Resources_Jobs_Props_JobProps {
        guard let client else { throw FiveNetError.notConnected }
        let updated = try await client.setJobProps(props)
        jobProps = updated
        return updated
    }

    /// Lists all roles of the active job.
    func getRoles(lowestRank: Bool? = nil) async throws -> [Resources_Permissions_Permissions_Role] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getRoles(lowestRank: lowestRank)
    }

    /// Creates a new role for the given job at the given grade.
    func createRole(job: String, grade: Int32) async throws -> Resources_Permissions_Permissions_Role {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createRole(job: job, grade: grade)
    }

    /// Deletes a role by id.
    func deleteRole(id: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteRole(id: id)
    }

    /// Fetches the effective (inherited) role, permissions and attributes.
    func getEffectivePermissions(roleId: Int64) async throws -> Services_Settings_GetEffectivePermissionsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getEffectivePermissions(roleId: roleId)
    }

    /// Views the audit log with optional filters and pagination.
    func viewAuditLog(search: String = "", actions: [Resources_Audit_EventAction] = [], results: [Resources_Audit_EventResult] = [], offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Settings_ViewAuditLogResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.viewAuditLog(search: search, actions: actions, results: results, offset: offset, pageSize: pageSize)
    }

    /// Lists the discord channels of the linked guild.
    func listDiscordChannels() async throws -> [Resources_Discord_Channel] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listDiscordChannels()
    }

    /// Lists the discord guilds the authenticated user is in.
    func listUserGuilds() async throws -> [Resources_Discord_Guild] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listUserGuilds()
    }

    /// Deletes the active job's logo.
    func deleteJobLogo() async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteJobLogo()
        if var props = jobProps {
            props.clearLogoFile()
            props.clearLogoFileID()
            jobProps = props
        }
    }

    // MARK: - Settings: Leitstelle (Centrum)

    /// Fetches the centrum settings.
    func getCentrumSettings() async throws -> Services_Centrum_GetSettingsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getCentrumSettings()
    }

    /// Updates the centrum settings.
    func updateCentrumSettings(_ settings: Resources_Centrum_Settings_Settings) async throws -> Resources_Centrum_Settings_Settings {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.updateCentrumSettings(settings)
    }

    // MARK: - Settings: Gesetzbücher (Laws)

    /// Lists all law books including their laws.
    func listLawBooks() async throws -> [Resources_Laws_LawBook] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listLawBooks()
    }

    /// Creates or updates a law book.
    func createOrUpdateLawBook(_ lawBook: Resources_Laws_LawBook) async throws -> Resources_Laws_LawBook {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createOrUpdateLawBook(lawBook)
    }

    /// Deletes a law book by id.
    func deleteLawBook(id: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteLawBook(id: id)
    }

    /// Creates or updates a law within a law book.
    func createOrUpdateLaw(_ law: Resources_Laws_Law) async throws -> Resources_Laws_Law {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createOrUpdateLaw(law)
    }

    /// Deletes a law by id.
    func deleteLaw(id: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteLaw(id: id)
    }

    // MARK: - Settings: Datenspeicher (Filestore)

    /// Lists files stored in the filestore.
    func listFiles(path: String = "", offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Filestore_ListFilesResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listFiles(path: path, offset: offset, pageSize: pageSize)
    }

    /// Deletes a file by id.
    func deleteFile(parentID: Int64, fileID: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteFile(parentID: parentID, fileID: fileID)
    }

    /// Deletes a file by path.
    func deleteFileByPath(path: String) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteFileByPath(path: path)
    }

    // MARK: - Settings: Konten (Accounts)

    /// Lists user accounts.
    func listAccounts(username: String = "", offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Settings_ListAccountsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listAccounts(username: username, offset: offset, pageSize: pageSize)
    }

    /// Enables/disables an account.
    func updateAccount(id: Int64, enabled: Bool) async throws -> Resources_Accounts_Account {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.updateAccount(id: id, enabled: enabled)
    }

    /// Deletes an account by id.
    func deleteAccount(id: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteAccount(id: id)
    }

    // MARK: - Settings: FiveNet-Einstellungen (Config)

    /// Fetches the server app config.
    func getAppConfig() async throws -> Resources_Settings_AppConfig {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getAppConfig()
    }

    // MARK: - Settings: Hintergrund-Aufgaben (Cron)

    /// Lists all background cron jobs.
    func listCronjobs() async throws -> [Resources_Cron_Cronjob] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listCronjobs()
    }

    /// Manually runs a cron job.
    func runCronjob(name: String) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.runCronjob(name: name)
    }

    // MARK: - Mail (Mailer)

    /// Lists the email accounts the active character can access.
    func listEmails(offset: Int64 = 0, pageSize: Int64 = 50, all: Bool = false) async throws -> Services_Mailer_ListEmailsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listEmails(offset: offset, pageSize: pageSize, all: all)
    }

    /// Fetches a single email account.
    func getEmail(id: Int64) async throws -> Resources_Mailer_Emails_Email {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getEmail(id: id)
    }

    /// Email address/domain proposals for the composer.
    func getEmailProposals(input: String) async throws -> Services_Mailer_GetEmailProposalsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getEmailProposals(input: input)
    }

    /// Lists threads for the given email accounts, optionally filtered by unread/archived.
    func listThreads(emailIds: [Int64], unread: Bool? = nil, archived: Bool? = nil, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Mailer_ListThreadsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listThreads(emailIds: emailIds, unread: unread, archived: archived, offset: offset, pageSize: pageSize)
    }

    /// Searches threads across all accessible emails, returning matching messages.
    func searchThreads(search: String, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Mailer_SearchThreadsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.searchThreads(search: search, offset: offset, pageSize: pageSize)
    }

    /// Fetches a single thread (with its state for the given email account).
    func getThread(emailID: Int64, threadID: Int64) async throws -> Resources_Mailer_Threads_Thread {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getThread(emailID: emailID, threadID: threadID)
    }

    /// Lists the messages of a thread.
    func listThreadMessages(emailID: Int64, threadID: Int64, offset: Int64 = 0, pageSize: Int64 = 50) async throws -> [Resources_Mailer_Messages_Message] {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listThreadMessages(emailID: emailID, threadID: threadID, offset: offset, pageSize: pageSize)
    }

    /// Creates a new thread with an initial message.
    func createThread(title: String, message: Resources_Mailer_Messages_Message, recipients: [String]) async throws -> Resources_Mailer_Threads_Thread {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createThread(title: title, message: message, recipients: recipients)
    }

    /// Posts a reply message into an existing thread.
    func postMessage(message: Resources_Mailer_Messages_Message, recipients: [String] = []) async throws -> Resources_Mailer_Messages_Message {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.postMessage(message: message, recipients: recipients)
    }

    /// Updates the per-email thread state (read/unread, archived, …).
    @discardableResult
    func setThreadState(_ state: Resources_Mailer_Threads_ThreadState) async throws -> Resources_Mailer_Threads_ThreadState {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.setThreadState(state)
    }

    /// Deletes a thread for the given email account.
    func deleteThread(emailID: Int64, threadID: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteThread(emailID: emailID, threadID: threadID)
    }

    /// Deletes a single message within a thread (JobAdmin).
    func deleteMessage(emailID: Int64, threadID: Int64, messageID: Int64) async throws {
        guard let client else { throw FiveNetError.notConnected }
        try await client.deleteMessage(emailID: emailID, threadID: threadID, messageID: messageID)
    }

    // MARK: - Qualifications (Qualifikationen)

    /// Lists qualifications, optionally filtered by search text.
    func listQualifications(search: String = "", offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Qualifications_ListQualificationsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listQualifications(search: search, offset: offset, pageSize: pageSize)
    }

    /// Fetches a single qualification.
    func getQualification(id: Int64) async throws -> Services_Qualifications_GetQualificationResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.getQualification(id: id)
    }

    /// Lists qualification results (own results by default).
    func listQualificationsResults(qualificationID: Int64? = nil, statuses: [Resources_Qualifications_ResultStatus] = [], userIds: [Int32] = [], offset: Int64 = 0, pageSize: Int64 = 50) async throws -> Services_Qualifications_ListQualificationsResultsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listQualificationsResults(qualificationID: qualificationID, statuses: statuses, userIds: userIds, offset: offset, pageSize: pageSize)
    }

    /// Lists qualification requests for a specific qualification (tutor view).
    func listQualificationRequests(qualificationID: Int64, statuses: [Resources_Qualifications_RequestStatus] = [], userIds: [Int32] = [], offset: Int64 = 0, pageSize: Int64 = 10) async throws -> Services_Qualifications_ListQualificationRequestsResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.listQualificationRequests(qualificationID: qualificationID, statuses: statuses, userIds: userIds, offset: offset, pageSize: pageSize)
    }

    /// Approves/denies/reopens a qualification request (tutor tab).
    func createOrUpdateQualificationRequest(request: Resources_Qualifications_QualificationRequest) async throws -> Services_Qualifications_CreateOrUpdateQualificationRequestResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createOrUpdateQualificationRequest(request: request)
    }

    /// Deletes a qualification request (tutor tab trash action).
    func deleteQualificationRequest(qualificationID: Int64, userID: Int32) async throws -> Services_Qualifications_DeleteQualificationReqResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.deleteQualificationRequest(qualificationID: qualificationID, userID: userID)
    }

    /// Creates or updates a qualification result (grading from the tutor tab).
    func createOrUpdateQualificationResult(result: Resources_Qualifications_QualificationResult) async throws -> Services_Qualifications_CreateOrUpdateQualificationResultResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.createOrUpdateQualificationResult(result: result)
    }

    /// Deletes a qualification result (tutor tab trash action).
    func deleteQualificationResult(resultID: Int64) async throws -> Services_Qualifications_DeleteQualificationResultResponse {
        guard let client else { throw FiveNetError.notConnected }
        return try await client.deleteQualificationResult(resultID: resultID)
    }

    // MARK: - Clipboard

    /// Copied citizens available for document templates ("Zwischenablage").
    private(set) var clipboardUsers: [Resources_Users_Short_UserShort] = []
    private(set) var clipboardDocuments: [Resources_Documents_Document] = []
    private(set) var clipboardVehicles: [Resources_Vehicles_Vehicle] = []

    /// Adds a citizen to the clipboard.
    func copyUserToClipboard(_ user: Resources_Users_Short_UserShort) {
        if !clipboardUsers.contains(where: { $0.userID == user.userID }) {
            clipboardUsers.insert(user, at: 0)
        }
    }

    /// Adds a document to the clipboard.
    func copyDocumentToClipboard(_ document: Resources_Documents_Document) {
        if !clipboardDocuments.contains(where: { $0.id == document.id }) {
            clipboardDocuments.insert(document, at: 0)
        }
    }

    /// Adds a vehicle to the clipboard.
    func copyVehicleToClipboard(_ vehicle: Resources_Vehicles_Vehicle) {
        if !clipboardVehicles.contains(where: { $0.plate == vehicle.plate }) {
            clipboardVehicles.insert(vehicle, at: 0)
        }
    }

    /// Clears all clipboard entries.
    func clearClipboard() {
        clipboardUsers = []
        clipboardDocuments = []
        clipboardVehicles = []
    }

    private static func describe(_ error: Error) -> String {
        if let fiveNet = error as? FiveNetError {
            return fiveNet.localizedDescription
        }
        return error.localizedDescription
    }

    /// Whether the error is a transient connection failure that the channel's
    /// auto-reconnect (and the stream restart backoff) heals on its own. Such
    /// failures must not raise an alarming full-screen alert — only permanent
    /// failures (reconnect keeps failing) should surface to the user.
    private static func isTransientConnectionError(_ error: Error) -> Bool {
        if let fiveNet = error as? FiveNetError {
            switch fiveNet {
            case .connectionClosed, .notConnected, .cancelled:
                return true
            case .invalidServerURL, .timeout, .invalidResponse, .grpcStatus,
                 .loginFailed, .unauthorized, .missingCharacter, .streamAlreadyExists,
                 .maxStreamsReached, .accountTokenMissing:
                return false
            }
        }
        return false
    }
}

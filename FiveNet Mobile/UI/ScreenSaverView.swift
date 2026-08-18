import SwiftUI
import Combine
import UIKit

/// Bildschirmschoner-Hülle für den gesamten App-Inhalt.
///
/// Blendet nach `idleDelay` Sekunden ohne Interaktion die FiveNet-Animation
/// ein und verschwindet bei jeder Interaktion sofort wieder. Nur im
/// Overview/den Modulen aktiv (`appState.phase == .overview`); sobald ein
/// Alarm-/Panic-Screen kommt, wird der Bildschirmschoner ausgeblendet.
///
/// Einstellbar über die Systemeinstellungen (Settings.bundle):
/// - `fivenetScreenSaverEnabled`: An/Aus
/// - `fivenetScreenSaverDelay`: Dauer in Sekunden bis zum Einblenden
struct ScreenSaverView<Content: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    let content: Content

    @State private var lastInteraction = Date()
    @State private var isShowing = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if isShowing {
                FiveNetAnimationView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .transition(.opacity)
                    .overlay(alignment: .topLeading) {
                        if openDispatchCount > 0 {
                            openDispatchBadge
                        }
                    }
            }
        }
        .background(InteractionSensor(onInteraction: { registerInteraction() }))
        .onAppear { lastInteraction = Date() }
        .onChange(of: scenePhase) { _, newPhase in
            lastInteraction = Date()
            if newPhase != .active {
                dismiss()
            }
        }
        .onChange(of: appState.activeAlarm?.id) { _, _ in
            // Alarm-/Panic-Screen überblendet den Bildschirmschoner.
            dismiss()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard canShowScreensaver, scenePhase == .active else {
                if isShowing {
                    dismiss()
                }
                return
            }
            if !isShowing, Date().timeIntervalSince(lastInteraction) >= idleDelay {
                withAnimation(.easeInOut(duration: 0.8)) {
                    isShowing = true
                }
            }
        }
    }

    /// Der Bildschirmschoner erscheint nur im Overview und den Modulen —
    /// nicht auf Login, Serverauswahl oder Charakterwahl. Im Dokumente-Modul
    /// wird er ebenfalls unterdrückt.
    private var canShowScreensaver: Bool {
        guard isScreensaverEnabled, appState.phase == .overview else { return false }
        guard appState.activeAlarm == nil else { return false }
        return appState.activeModule != .documents
    }

    /// Der Toggle wird direkt aus den Systemeinstellungen gelesen (Settings.bundle
    /// schreibt in den Standard-UserDefaults-Bereich), damit Änderungen an der
    /// Systemeinstellungen-App auch bei laufender App sofort greifen.
    private var isScreensaverEnabled: Bool {
        if UserDefaults.standard.object(forKey: "fivenetScreenSaverEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "fivenetScreenSaverEnabled")
        }
        return true
    }

    /// Dauer bis zum Einblenden, konfigurierbar über die Systemeinstellungen.
    private var idleDelay: TimeInterval {
        if UserDefaults.standard.object(forKey: "fivenetScreenSaverDelay") != nil {
            let seconds = UserDefaults.standard.double(forKey: "fivenetScreenSaverDelay")
            return max(5, min(seconds, 300))
        }
        return ScreenSaverDispatches.defaultIdleDelay
    }

    private var openDispatchCount: Int {
        let ownUnitID = appState.ownUnitID
        return appState.dispatches.filter { dispatch in
            ScreenSaverDispatches.shownStatuses.contains(dispatch.status.status)
                && !ScreenSaverDispatches.closedStatuses.contains(dispatch.status.status)
                && !(ownUnitID != nil && dispatch.units.contains { $0.unitID == ownUnitID })
        }.count
    }

    private var openDispatchBadge: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.warning)
            Text(openDispatchCount, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.black.opacity(0.55), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.leading, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xxl)
        .accessibilityLabel("\(openDispatchCount) offene Einsätze")
    }

    private func registerInteraction() {
        lastInteraction = Date()
        if isShowing {
            dismiss()
        }
    }

    private func dismiss() {
        guard isShowing else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowing = false
        }
    }
}

/// Beobachtet jede Berührung im gesamten App-Fenster über UIKit-Gesten, ohne
/// die Touch-Verarbeitung von Buttons/ScrollViews/NavigationLinks zu stören
/// (`cancelsTouchesInView = false`). Ersetzt die früheren SwiftUI-`.simultaneousGesture`
/// auf dem Content, die alle Buttons blockiert haben.
private struct InteractionSensor: UIViewRepresentable {
    let onInteraction: () -> Void

    func makeUIView(context: Context) -> InteractionSensorView {
        let view = InteractionSensorView()
        view.onInteraction = onInteraction
        return view
    }

    func updateUIView(_ uiView: InteractionSensorView, context: Context) {
        uiView.onInteraction = onInteraction
    }
}

private final class InteractionSensorView: UIView {
    var onInteraction: (() -> Void)?

    private var sensorWindow: UIWindow?
    private var sensorRecognizers: [UIGestureRecognizer] = []

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if let sensorWindow {
            for recognizer in sensorRecognizers {
                sensorWindow.removeGestureRecognizer(recognizer)
            }
            sensorRecognizers.removeAll()
            self.sensorWindow = nil
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, sensorWindow !== window else { return }
        sensorWindow = window
        installGestures(on: window!)
    }

    private func installGestures(on window: UIWindow) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleGesture))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        sensorRecognizers.append(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleGesture))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        window.addGestureRecognizer(pan)
        sensorRecognizers.append(pan)
    }

    @objc private func handleGesture() {
        onInteraction?()
    }
}

extension InteractionSensorView: UIGestureRecognizerDelegate {
    /// Erlaubt das gleichzeitige Erkennen mit allen anderen Gesten, damit
    /// Buttons/NavigationLinks/ScrollViews ungestört funktionieren.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Statusmengen für den „offene Einsätze"-Zähler des Bildschirmschoners
/// (außerhalb der generischen View — statische Stored Properties sind dort
/// nicht erlaubt).
private enum ScreenSaverDispatches {
    /// Default-Dauer bis zum Einblenden in Sekunden.
    static let defaultIdleDelay: TimeInterval = 15

    static let closedStatuses: Set<Resources_Centrum_Dispatches_StatusDispatch> = [
        .completed, .cancelled, .archived, .deleted,
    ]

    static let shownStatuses: Set<Resources_Centrum_Dispatches_StatusDispatch> = [
        .new, .unassigned, .updated, .unitAssigned, .unitUnassigned,
        .unitAccepted, .unitDeclined, .enRoute, .onScene, .needAssistance,
    ]
}
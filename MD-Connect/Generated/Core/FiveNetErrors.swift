import Foundation

enum FiveNetError: LocalizedError {
    case invalidServerURL
    case notConnected
    case connectionClosed
    case timeout
    case invalidResponse(String)
    case grpcStatus(code: Int, message: String)
    case loginFailed(String)
    case unauthorized
    case missingCharacter
    case streamAlreadyExists
    case maxStreamsReached
    case cancelled
    case accountTokenMissing

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Die Server-URL ist ungültig."
        case .notConnected:
            return "Keine Verbindung zum FiveNet-Server."
        case .connectionClosed:
            return "Die Verbindung zum FiveNet-Server wurde geschlossen."
        case .timeout:
            return "Die Anfrage hat das Zeitlimit überschritten."
        case .invalidResponse(let detail):
            return "Der Server hat eine ungültige Antwort gesendet: \(detail)"
        case .grpcStatus(let code, let message):
            return Self.friendlyGRPCError(code: code, message: message)
        case .loginFailed(let message):
            return message.isEmpty ? "Anmeldung fehlgeschlagen." : message
        case .unauthorized:
            return "Die Sitzung ist nicht mehr gültig. Bitte melde dich erneut an."
        case .missingCharacter:
            return "Es wurde kein Charakter ausgewählt."
        case .streamAlreadyExists:
            return "Der Stream existiert bereits."
        case .maxStreamsReached:
            return "Zu viele gleichzeitige Anfragen."
        case .cancelled:
            return "Die Anfrage wurde abgebrochen."
        case .accountTokenMissing:
            return "Kein Session-Token vom Server erhalten."
        }
    }

    /// Maps the server's i18n error JSON (or generic gRPC messages) to a readable
    /// German description.
    static func friendlyGRPCError(code: Int, message: String) -> String {
        if message.contains("ErrInvalidLogin") {
            return "Benutzername oder Passwort ist falsch."
        }
        if message.contains("ErrInvalidToken") {
            return "Die Sitzung ist abgelaufen oder ungültig. Bitte melde dich erneut an."
        }
        if message.contains("ErrCharLock") {
            return "Dieser Charakter ist gerade gesperrt. Du musst erst mit diesem Charakter im Spiel aktiv sein, bevor du in der App auf ihn zugreifen kannst."
        }
        if message.contains("ErrNotOnDuty") {
            return "Du bist gerade nicht im Dienst. Beginne zuerst deinen Dienst, um diese Aktion auszuführen."
        }
        if message.contains("ErrDiscordNotEnabled") {
            return "Discord ist nicht aktiviert."
        }
        let msg = message.isEmpty ? "Unbekannter Fehler" : message
        return "Serverfehler (\(code)): \(msg)"
    }
}

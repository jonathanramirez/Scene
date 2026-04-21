import Foundation
import Observation

/// Per-document session state shared across Reader, Practice, and Lyrics.
/// Injected via environment so all views read and write the same instance.
@Observable
final class ScriptSessionState {
    // Identity
    let documentID: UUID

    // Reading
    var currentPage: Int = 0

    // Practice / Lyrics context
    var selectedCharacter: String? = nil
    var currentTurnIndex: Int? = nil
    var memoryMode: Bool = false
    var readAloudEnabled: Bool = true
    var speechRate: Float = 0.5

    init(documentID: UUID) {
        self.documentID = documentID
    }
}

/// App-wide store that vends one ScriptSessionState per document.
/// Inject this at the root via `.environment`.
@Observable
final class ScriptSessionStore {
    private var sessions: [UUID: ScriptSessionState] = [:]

    func session(for documentID: UUID) -> ScriptSessionState {
        if let existing = sessions[documentID] { return existing }
        let new = ScriptSessionState(documentID: documentID)
        sessions[documentID] = new
        return new
    }
}

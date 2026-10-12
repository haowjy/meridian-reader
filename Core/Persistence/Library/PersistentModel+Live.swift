import SwiftData

extension PersistentModel {
    /// Still in the store: not deleted, and still in a context. A saved delete reaches the views
    /// holding the model (a row, a folder's screen, a relationship's stale members) before their
    /// lists drop it, so they draw once more with it; reading an attribute it hadn't loaded then
    /// traps in SwiftData. Once a delete is saved `isDeleted` reads false again, so the context is
    /// what tells.
    var isLive: Bool { !isDeleted && modelContext != nil }
}

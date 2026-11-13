import Foundation

/// Decides which Short each of the Shorts player's web-view slots holds.
///
/// The Shorts pager keeps a small fixed pool of embed players (live Short plus its
/// neighbours, preloaded and paused on their first frame). A slot never changes its
/// place in the view hierarchy — moving a WKWebView between containers leaves it
/// black (#279) — so paging only changes *which video* each slot holds. This keeps a
/// slot's video whenever it is still wanted, so a swipe onto a preloaded Short reuses
/// it instead of reloading.
public enum ShortsSlotPlanner {

    /// - Parameters:
    ///   - held: the video id each slot currently holds (`nil` = empty slot).
    ///   - wanted: the video ids to keep loaded, most important first (live, next,
    ///     previous). Duplicates are ignored.
    /// - Returns: per slot, the video it must hold, or `nil` when the slot isn't
    ///   needed (it keeps whatever it has). A slot already holding a wanted video
    ///   keeps it; missing videos go to the remaining slots in priority order.
    public static func plan(held: [String?], wanted: [String]) -> [String?] {
        var wantedUnique: [String] = []
        for id in wanted where !wantedUnique.contains(id) {
            wantedUnique.append(id)
        }

        var result: [String?] = Array(repeating: nil, count: held.count)
        var placed = Set<String>()
        for (slot, id) in held.enumerated() {
            guard let id, wantedUnique.contains(id), !placed.contains(id) else { continue }
            result[slot] = id
            placed.insert(id)
        }

        var freeSlots = result.indices.filter { result[$0] == nil }
        for id in wantedUnique where !placed.contains(id) {
            guard !freeSlots.isEmpty else { break }
            result[freeSlots.removeFirst()] = id
            placed.insert(id)
        }
        return result
    }
}

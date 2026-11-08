import CryptoKit
import Darwin
import Foundation

/// What the duplicate finder found.
struct DuplicateResult: Sendable {
    /// One suggestion for each set of same-content files, the largest saving first.
    var groups: [Suggestion] = []
    /// The bytes read, partial and full hashes together.
    var hashed: Int64 = 0
    /// A budget or a cancel stopped the work before every group was checked.
    var partial = false
    /// The files that a budget left out (`hashBudget`).
    var skips = ScanSkips()
    /// Every file that was opened for hashing. Reading changes the access date, so the scan keeps these.
    var hashedFiles: [FileID] = []
}

/// Finds files with the same content. A hard link is one file. Files of one size get a hash of their first
/// and last 64 KiB, and only the files that still match are read in full.
enum DuplicateFinder {
    static let chunk = 1_048_576
    static let edge: Int64 = 65_536

    /// - Parameter progress: the full-hash bytes read so far, and the total that is planned.
    static func groups(_ candidates: [DuplicateCandidate], fs: any ScanFileSystem, config: SuggestionConfig,
                       ignores: SuggestionIgnores.Snapshot, isCancelled: () -> Bool,
                       progress: (Int64, Int64) -> Void) -> DuplicateResult {
        var result = DuplicateResult()
        let start = config.elapsed()
        func timeUp() -> Bool { config.elapsed() - start > config.hashTimeBudget }
        func cancelled() -> DuplicateResult {
            var r = result
            r.partial = true
            r.groups = []
            return r
        }
        func skip(_ list: [DuplicateCandidate]) {
            result.partial = true
            for c in list { result.skips.add(.hashBudget, path: c.item.url.path) }
        }

        // 1. One path for each inode. Another link frees nothing.
        var seen = Set<FileID>()
        var files: [DuplicateCandidate] = []
        for c in candidates.sorted(by: { $0.item.id < $1.item.id })
        where c.item.bytes >= config.duplicateMin && c.item.logicalBytes > 0 && seen.insert(c.fileID).inserted {
            files.append(c)
        }

        // 2. Same size.
        let bySize = Dictionary(grouping: files) { $0.item.logicalBytes }.values.filter { $0.count > 1 }

        // 3. Same first and last 64 KiB.
        var matching: [[DuplicateCandidate]] = []
        var stopped = false
        for same in bySize.sorted(by: { order($0, $1) }) {
            if isCancelled() { return cancelled() }
            if stopped || timeUp() { stopped = true; skip(same); continue }
            let size = same[0].item.logicalBytes
            let ranges: [Range<Int64>] = size <= 2 * edge ? [0..<size] : [0..<edge, (size - edge)..<size]
            var byHash: [String: [DuplicateCandidate]] = [:]
            for c in same {
                result.hashedFiles.append(c.fileID)
                guard let sha = sha256(c.item.url, ranges: ranges, isCancelled: isCancelled, onChunk: { result.hashed += Int64($0) }) else {
                    if isCancelled() { return cancelled() }
                    continue
                }
                byHash[sha, default: []].append(c)
            }
            matching += byHash.values.filter { $0.count > 1 }
        }

        // 4. Full hash, the largest saving first.
        matching.sort(by: order)
        let planned = matching.reduce(Int64(0)) { $0 + $1[0].item.logicalBytes * Int64($1.count) }
        var full: Int64 = 0
        stopped = false
        var found: [(sha: String, copies: [DuplicateCandidate])] = []
        for same in matching {
            if isCancelled() { return cancelled() }
            if stopped || timeUp() { stopped = true; skip(same); continue }
            if full + same[0].item.logicalBytes * Int64(same.count) > config.hashBudgetBytes { skip(same); continue }
            var byHash: [String: [DuplicateCandidate]] = [:]
            for c in same {
                guard let sha = sha256(c.item.url, range: nil, isCancelled: isCancelled, onChunk: {
                    full += Int64($0)
                    result.hashed += Int64($0)
                    progress(full, planned)
                }) else {
                    if isCancelled() { return cancelled() }
                    continue
                }
                byHash[sha, default: []].append(c)
            }
            for (sha, copies) in byHash where copies.count > 1 { found.append((sha, copies)) }
        }

        // 5. One suggestion for each set.
        for (sha, copies) in found where !ignores.coversHash(sha) {
            if let s = suggestion(sha: sha, copies: copies, fs: fs, config: config, ignores: ignores) { result.groups.append(s) }
        }
        result.groups.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
        return result
    }

    /// The group with the larger saving first, then by path.
    private static func order(_ a: [DuplicateCandidate], _ b: [DuplicateCandidate]) -> Bool {
        let (x, y) = (a[0].item.logicalBytes * Int64(a.count - 1), b[0].item.logicalBytes * Int64(b.count - 1))
        return x != y ? x > y : a.map(\.item.id).min()! < b.map(\.item.id).min()!
    }

    private static func suggestion(sha: String, copies: [DuplicateCandidate], fs: any ScanFileSystem, config: SuggestionConfig,
                                   ignores: SuggestionIgnores.Snapshot) -> Suggestion? {
        let items = copies.map(\.item)
        let ignored = items.filter { ignores.covers($0.id) }
        let home = config.home.path
        let dropFolders = [home + "/Downloads", home + "/Desktop", home + "/.Trash"]
        func inDropFolder(_ item: SuggestionItem) -> Bool {
            dropFolders.contains { item.id == $0 || item.id.hasPrefix($0 + "/") }
        }
        // The kept copy: an ignored one, one outside the drop folders, the newest, the shortest path, the lowest path.
        let keep = (ignored.isEmpty ? items : ignored).min { a, b in
            if inDropFolder(a) != inDropFolder(b) { return !inDropFolder(a) }
            let (da, db) = (a.date ?? .distantPast, b.date ?? .distantPast)
            if da != db { return da > db }
            if a.id.count != b.id.count { return a.id.count < b.id.count }
            return a.id < b.id
        }!
        // Another ignored copy is never offered, so it leaves the group.
        let others = items.filter { $0.id != keep.id && !ignores.covers($0.id) }.sorted { $0.id < $1.id }
        guard !others.isEmpty else { return nil }
        let ordered = [keep] + others
        let share = ordered.contains { fs.mayShareBlocks($0.url) }
        let reason = SuggestionReason.sameContent(copies: ordered.count, sha256: sha, mayShareBlocks: share)
        return Suggestion(kind: .duplicates, id: "dup:" + sha, items: ordered, keep: keep.url,
                          bytes: Suggestion.saving(ordered, keep: keep.url, reason: reason), reason: reason)
    }

    /// The SHA-256 of a file (all of it, or one `range`) as lowercase hex. The file is read in 1 MiB pieces
    /// with the cache off, and `isCancelled` is asked before each piece. Nil when it is cancelled or cannot be read.
    static func sha256(_ url: URL, range: Range<Int64>?, isCancelled: () -> Bool, onChunk: (Int) -> Void = { _ in }) -> String? {
        sha256(url, ranges: range.map { [$0] }, isCancelled: isCancelled, onChunk: onChunk)
    }

    private static func sha256(_ url: URL, ranges: [Range<Int64>]?, isCancelled: () -> Bool, onChunk: (Int) -> Void) -> String? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        // A file that went to the cloud since the walk is not read, because the read would download it.
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_flags & 0x4000_0000 == 0 else { return nil }  // SF_DATALESS
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunk)
        for range in ranges ?? [0..<Int64.max] {
            var offset = range.lowerBound
            while offset < range.upperBound {
                if isCancelled() { return nil }
                let want = Int(min(Int64(chunk), range.upperBound - offset))
                let got = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, want, off_t(offset)) }
                if got < 0 { return nil }
                if got == 0 { break }
                hasher.update(data: buffer[0..<got])
                offset += Int64(got)
                onChunk(got)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

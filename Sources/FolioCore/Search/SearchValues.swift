import Foundation

/// Reads `size:` and `date:` values: Windows 11's size words and byte units, comparisons, ranges,
/// and calendar periods (today, this week, last month...) and explicit dates.
public enum SearchValues {
    // MARK: Size

    /// The size words and their inclusive byte ranges, on the same edges as the Size filter's buckets
    /// (Windows 10 1809 and later, binary units).
    public static let sizeWords: [(word: String, range: SizeRange)] = {
        var out: [(String, SizeRange)] = []
        var lower: Int64 = 0
        for (top, bucket) in Buckets.sizeBuckets {
            out.append((bucket.id, SizeRange(lower, top == Int64.max ? nil : top)))
            if top < Int64.max { lower = top + 1 }
        }
        return out
    }()

    public static func sizeWord(_ word: String) -> SizeRange? {
        sizeWords.first { $0.word == word.lowercased() }?.range
    }

    /// `500`, `10kb`, `1.5MB`, `2g`: bytes (no unit is bytes; units are binary).
    public static func bytes(_ raw: String) -> Int64? {
        let s = raw.lowercased()
        let units: [(String, Double)] = [("tb", 1_099_511_627_776), ("gb", 1_073_741_824), ("mb", 1_048_576), ("kb", 1024),
                                         ("t", 1_099_511_627_776), ("g", 1_073_741_824), ("m", 1_048_576), ("k", 1024), ("b", 1)]
        var number = s, factor: Double = 1
        for (suffix, f) in units where s.hasSuffix(suffix) {
            number = String(s.dropLast(suffix.count))
            factor = f
            break
        }
        guard !number.isEmpty, number.allSatisfy({ $0.isNumber || $0 == "." }), let n = Double(number), n >= 0 else { return nil }
        return Int64((n * factor).rounded())
    }

    /// A size value with its operator: a word, a number with a unit, or a range `a..b`.
    public static func size(_ raw: String, op: String) -> SizeRange? {
        if let dots = raw.range(of: "..") {
            let a = String(raw[..<dots.lowerBound]), b = String(raw[dots.upperBound...])
            guard let ra = sizeOne(a), let rb = sizeOne(b) else { return nil }
            return SizeRange(ra.lower, rb.upper)
        }
        guard let r = sizeOne(raw) else { return nil }
        switch op {
        case ">": return r.upper.map { SizeRange($0 + 1, nil) } ?? SizeRange(Int64.max, nil)
        case ">=", "\u{2265}": return SizeRange(r.lower, nil)
        case "<": return SizeRange(nil, (r.lower ?? 0) - 1)
        case "<=", "\u{2264}": return SizeRange(nil, r.upper)
        case "", "=": return r
        default: return nil
        }
    }

    /// One word or number, as the range it stands for (a number is exactly that many bytes).
    static func sizeOne(_ raw: String) -> SizeRange? {
        if let w = sizeWord(raw) { return w }
        return bytes(raw).map { SizeRange($0, $0) }
    }

    // MARK: Dates

    /// A date value with its operator: a period, an explicit date, or a range `a..b` (inclusive of both
    /// ends' whole periods). Bounds are [start, end).
    public static func date(_ raw: String, op: String, context: BucketContext) -> DateBounds? {
        if let dots = raw.range(of: "..") {
            let a = String(raw[..<dots.lowerBound]), b = String(raw[dots.upperBound...])
            guard let pa = period(a, context), let pb = period(b, context) else { return nil }
            return DateBounds(min(pa.start, pb.start), max(pa.end, pb.end))
        }
        guard let p = period(raw, context) else { return nil }
        switch op {
        case "", "=": return DateBounds(p.start, p.end)
        case ">": return DateBounds(p.end, nil)
        case ">=", "\u{2265}": return DateBounds(p.start, nil)
        case "<": return DateBounds(nil, p.start)
        case "<=", "\u{2264}": return DateBounds(nil, p.end)
        default: return nil
        }
    }

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                                 "october", "november", "december"]

    /// The calendar period a word or date names: today is midnight to midnight, this week starts on the
    /// calendar's first weekday, last month is the whole previous month.
    public static func period(_ raw: String, _ context: BucketContext) -> DateInterval? {
        let cal = context.calendar
        let now = context.now
        let word = raw.lowercased()
        func span(_ unit: Calendar.Component, _ offset: Int) -> DateInterval? {
            let base: Date? = switch unit {
            case .day: cal.startOfDay(for: now)
            case .weekOfYear: cal.dateInterval(of: .weekOfYear, for: now)?.start
            case .month: cal.dateInterval(of: .month, for: now)?.start
            default: cal.dateInterval(of: .year, for: now)?.start
            }
            let step: Calendar.Component = unit == .weekOfYear ? .day : unit
            let amount = unit == .weekOfYear ? 7 : 1
            guard let base, let start = cal.date(byAdding: step, value: offset * amount, to: base),
                  let end = cal.date(byAdding: step, value: amount, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
        switch word {
        case "today": return span(.day, 0)
        case "yesterday": return span(.day, -1)
        case "tomorrow": return span(.day, 1)
        case "thisweek": return span(.weekOfYear, 0)
        case "lastweek", "pastweek": return span(.weekOfYear, -1)
        case "nextweek": return span(.weekOfYear, 1)
        case "thismonth": return span(.month, 0)
        case "lastmonth", "pastmonth": return span(.month, -1)
        case "nextmonth": return span(.month, 1)
        case "thisyear": return span(.year, 0)
        case "lastyear", "pastyear": return span(.year, -1)
        case "nextyear", "comingyear": return span(.year, 1)
        default: break
        }
        // Monday: that day of this week. February: that month of this year.
        if let w = weekdays.firstIndex(where: { $0 == word || ($0.hasPrefix(word) && word.count >= 3) }),
           let week = cal.dateInterval(of: .weekOfYear, for: now) {
            var day = week.start
            while cal.component(.weekday, from: day) != w + 1 { day = cal.date(byAdding: .day, value: 1, to: day)! }
            return DateInterval(start: day, end: cal.date(byAdding: .day, value: 1, to: day)!)
        }
        if let m = months.firstIndex(where: { $0 == word || ($0.hasPrefix(word) && word.count >= 3) }) {
            var c = cal.dateComponents([.year], from: now)
            c.month = m + 1
            c.day = 1
            guard let start = cal.date(from: c) else { return nil }
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
        }
        return explicit(raw, context)
    }

    /// 2024-03-01, 2024-03, 2024, and slashed or dotted dates in the user's day/month order.
    static func explicit(_ raw: String, _ context: BucketContext) -> DateInterval? {
        let cal = context.calendar
        func make(_ y: Int, _ m: Int?, _ d: Int?) -> DateInterval? {
            guard (1...9999).contains(y) else { return nil }
            var c = DateComponents()
            c.year = y
            c.month = m ?? 1
            c.day = d ?? 1
            guard let mm = c.month, (1...12).contains(mm), let dd = c.day, (1...31).contains(dd),
                  let start = cal.date(from: c), cal.component(.month, from: start) == mm else { return nil }
            let unit: Calendar.Component = d != nil ? .day : (m != nil ? .month : .year)
            return DateInterval(start: start, end: cal.date(byAdding: unit, value: 1, to: start)!)
        }
        let digitsOnly = raw.allSatisfy(\.isNumber)
        if digitsOnly, raw.count == 4, let y = Int(raw) { return make(y, nil, nil) }
        // ISO: 2024-03-01, 2024-03, 2024-03-01T10:00:00 (the day).
        let iso = raw.split(separator: "T").first.map(String.init) ?? raw
        let dash = iso.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if dash.count >= 2, dash.count <= 3, dash[0].count == 4, dash.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return make(Int(dash[0])!, Int(dash[1]), dash.count == 3 ? Int(dash[2]) : nil)
        }
        for sep in ["/", "."] {
            let parts = raw.split(separator: Character(sep), omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { continue }
            var y = Int(parts[2])!
            if parts[2].count <= 2 { y += y < 70 ? 2000 : 1900 }
            let a = Int(parts[0])!, b = Int(parts[1])!
            let dayFirst = sep == "." || dayComesFirst(cal.locale ?? Locale(identifier: "en_US"))
            return dayFirst ? make(y, b, a) : make(y, a, b)
        }
        return nil
    }

    /// True where the short date reads day before month (en_GB, de_DE), false for en_US.
    static func dayComesFirst(_ locale: Locale) -> Bool {
        let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        guard let d = pattern.firstIndex(of: "d"), let m = pattern.firstIndex(of: "M") else { return false }
        return d < m
    }
}

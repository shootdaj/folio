import Foundation

/// Back/Forward/Up history for one window, like Windows Explorer: Up is a normal step you can go Back from.
public struct NavigationHistory: Sendable {
    public private(set) var current: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    public init(start: URL) {
        current = start.standardizedFileURL
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var canGoUp: Bool { Self.parent(of: current) != nil }

    /// Goes to a new folder and drops the forward stack. Pushing the current folder does nothing.
    public mutating func push(_ url: URL) {
        let url = url.standardizedFileURL
        guard url.path != current.path else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = url
    }

    public mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return current
    }

    public mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return current
    }

    public mutating func goUp() -> URL? {
        guard let parent = Self.parent(of: current) else { return nil }
        push(parent)
        return current
    }

    public static func parent(of url: URL) -> URL? {
        let url = url.standardizedFileURL
        guard url.path != "/" else { return nil }
        return url.deletingLastPathComponent().standardizedFileURL
    }
}

import Foundation

/// Owns document-tab identity, ordering and selection without knowing the UI.
public struct DocumentTabSession: Equatable, Sendable {
    public private(set) var tabs: [DocumentTab]
    public private(set) var activeTabID: String?

    public init(tabs: [DocumentTab] = [], activeTabID: String? = nil) {
        var uniqueTabs: [DocumentTab] = []
        var seenURLs = Set<URL>()
        for tab in tabs {
            let normalizedURL = tab.isUntitled ? tab.url : tab.url.standardizedFileURL
            guard seenURLs.insert(normalizedURL).inserted else { continue }
            uniqueTabs.append(tab)
        }
        self.tabs = uniqueTabs
        self.activeTabID = activeTabID.flatMap { id in
            uniqueTabs.contains { $0.id == id } ? id : nil
        } ?? uniqueTabs.first?.id
    }

    public var activeTab: DocumentTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    @discardableResult
    public mutating func open(_ tab: DocumentTab) -> Bool {
        let normalizedURL = tab.url.standardizedFileURL
        if let existing = tabs.first(where: { $0.url.standardizedFileURL == normalizedURL }) {
            activeTabID = existing.id
            return false
        }
        tabs.append(tab)
        activeTabID = tab.id
        return true
    }

    @discardableResult
    public mutating func select(id: String) -> Bool {
        guard tabs.contains(where: { $0.id == id }) else { return false }
        activeTabID = id
        return true
    }

    @discardableResult
    public mutating func selectNext() -> Bool {
        guard !tabs.isEmpty else { return false }
        guard let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            self.activeTabID = tabs[0].id
            return true
        }
        self.activeTabID = tabs[(index + 1) % tabs.count].id
        return true
    }

    @discardableResult
    public mutating func close(id: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let wasActive = activeTabID == id
        tabs.remove(at: index)
        if wasActive {
            activeTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        } else if tabs.isEmpty {
            activeTabID = nil
        }
        return true
    }

    @discardableResult
    public mutating func closeOthers(keeping id: String) -> Bool {
        guard let tab = tabs.first(where: { $0.id == id }) else { return false }
        tabs = [tab]
        activeTabID = tab.id
        return true
    }

    @discardableResult
    public mutating func closeToRight(of id: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs = Array(tabs.prefix(through: index))
        if let activeTabID, !tabs.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = tabs.last?.id
        }
        return true
    }

    @discardableResult
    public mutating func move(_ id: String, before targetID: String) -> Bool {
        guard id != targetID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == id }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID }) else {
            return false
        }

        let tab = tabs.remove(at: sourceIndex)
        let adjustedTargetIndex = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
        tabs.insert(tab, at: adjustedTargetIndex)
        return true
    }

    @discardableResult
    public mutating func moveToEnd(_ id: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              index != tabs.index(before: tabs.endIndex) else { return false }
        let tab = tabs.remove(at: index)
        tabs.append(tab)
        return true
    }

    @discardableResult
    public mutating func reorder(ids: [String]) -> Bool {
        guard ids.count == tabs.count,
              Set(ids) == Set(tabs.map(\.id)) else { return false }
        let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        tabs = ids.compactMap { tabsByID[$0] }
        return true
    }

    @discardableResult
    public mutating func update(id: String, _ change: (inout DocumentTab) -> Void) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        change(&tabs[index])
        return true
    }

    public func tab(id: String) -> DocumentTab? {
        tabs.first { $0.id == id }
    }

    public var persistedPaths: [String] {
        tabs.filter { !$0.isUntitled }.map(\.url.path)
    }
}

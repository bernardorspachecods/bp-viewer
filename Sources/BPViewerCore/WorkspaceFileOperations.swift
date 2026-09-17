import Foundation

public enum WorkspaceFileOperationError: Error, Equatable, LocalizedError, Sendable {
    case invalidWorkspaceRoot
    case itemNotFound
    case itemIsWorkspaceRoot
    case itemOutsideWorkspace
    case destinationOutsideWorkspace
    case destinationNotDirectory
    case destinationInsideItem
    case invalidName
    case itemAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .invalidWorkspaceRoot:
            "The workspace root is not a readable folder."
        case .itemNotFound:
            "The selected item no longer exists."
        case .itemIsWorkspaceRoot:
            "The workspace root cannot be changed by this action."
        case .itemOutsideWorkspace:
            "The selected item is outside the workspace."
        case .destinationOutsideWorkspace:
            "Choose a folder inside the workspace."
        case .destinationNotDirectory:
            "The destination is not a folder."
        case .destinationInsideItem:
            "An item cannot be moved into itself."
        case .invalidName:
            "Enter a valid name without path separators."
        case .itemAlreadyExists:
            "An item with that name already exists."
        }
    }
}

public enum WorkspaceFileOperations {
    @discardableResult
    public static func rename(
        itemAt url: URL,
        to name: String,
        in root: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let itemURL = try validateItem(url, in: root, fileManager: fileManager)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmedName) else {
            throw WorkspaceFileOperationError.invalidName
        }

        let destinationName = namePreservingExistingExtension(
            trimmedName,
            for: itemURL
        )
        let destinationURL = itemURL.deletingLastPathComponent()
            .appendingPathComponent(destinationName, isDirectory: isDirectory(itemURL, fileManager: fileManager))
        guard destinationURL.standardizedFileURL != itemURL.standardizedFileURL else {
            return itemURL
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw WorkspaceFileOperationError.itemAlreadyExists
        }

        try fileManager.moveItem(at: itemURL, to: destinationURL)
        return destinationURL
    }

    @discardableResult
    public static func duplicate(
        itemAt url: URL,
        in root: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let itemURL = try validateItem(url, in: root, fileManager: fileManager)
        let destinationURL = uniqueCopyURL(for: itemURL, fileManager: fileManager)
        try fileManager.copyItem(at: itemURL, to: destinationURL)
        return destinationURL
    }

    @discardableResult
    public static func move(
        itemAt url: URL,
        to directory: URL,
        in root: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let itemURL = try validateItem(url, in: root, fileManager: fileManager)
        let destinationDirectory = try validateDestination(directory, in: root, fileManager: fileManager)
        guard !isWithin(destinationDirectory, itemURL) else {
            throw WorkspaceFileOperationError.destinationInsideItem
        }

        let destinationURL = destinationDirectory.appendingPathComponent(
            itemURL.lastPathComponent,
            isDirectory: isDirectory(itemURL, fileManager: fileManager)
        )
        guard destinationURL.standardizedFileURL != itemURL.standardizedFileURL else {
            return itemURL
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw WorkspaceFileOperationError.itemAlreadyExists
        }

        try fileManager.moveItem(at: itemURL, to: destinationURL)
        return destinationURL
    }

    public static func remove(
        itemAt url: URL,
        in root: URL,
        fileManager: FileManager = .default
    ) throws {
        let itemURL = try validateItem(url, in: root, fileManager: fileManager)
        try fileManager.trashItem(at: itemURL, resultingItemURL: nil)
    }

    private static func validateItem(
        _ url: URL,
        in root: URL,
        fileManager: FileManager
    ) throws -> URL {
        let rootURL = try validateRoot(root, fileManager: fileManager)
        let itemURL = url.standardizedFileURL
        guard fileManager.fileExists(atPath: itemURL.path) else {
            throw WorkspaceFileOperationError.itemNotFound
        }

        let resolvedItemURL = itemURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedItemURL != rootURL,
              isWithin(resolvedItemURL, rootURL) else {
            if resolvedItemURL == rootURL {
                throw WorkspaceFileOperationError.itemIsWorkspaceRoot
            }
            throw WorkspaceFileOperationError.itemOutsideWorkspace
        }
        return itemURL
    }

    private static func validateDestination(
        _ url: URL,
        in root: URL,
        fileManager: FileManager
    ) throws -> URL {
        let rootURL = try validateRoot(root, fileManager: fileManager)
        let destinationURL = url.standardizedFileURL
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw WorkspaceFileOperationError.destinationNotDirectory
        }
        guard isDirectory(destinationURL, fileManager: fileManager) else {
            throw WorkspaceFileOperationError.destinationNotDirectory
        }

        let resolvedDestinationURL = destinationURL.resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(resolvedDestinationURL, rootURL) else {
            throw WorkspaceFileOperationError.destinationOutsideWorkspace
        }
        return destinationURL
    }

    private static func validateRoot(
        _ root: URL,
        fileManager: FileManager
    ) throws -> URL {
        let rootURL = root.standardizedFileURL
        guard fileManager.fileExists(atPath: rootURL.path),
              isDirectory(rootURL, fileManager: fileManager) else {
            throw WorkspaceFileOperationError.invalidWorkspaceRoot
        }
        return rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isWithin(_ child: URL, _ parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":")
    }

    private static func namePreservingExistingExtension(_ name: String, for url: URL) -> String {
        guard !url.pathExtension.isEmpty,
              !name.hasSuffix("."),
              URL(fileURLWithPath: name).pathExtension.isEmpty else {
            return name
        }
        return "\(name).\(url.pathExtension)"
    }

    private static func uniqueCopyURL(for url: URL, fileManager: FileManager) -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        let suffix = extensionName.isEmpty ? "" : ".\(extensionName)"
        let firstName = "\(baseName) copy\(suffix)"
        let parent = url.deletingLastPathComponent()
        var candidate = parent.appendingPathComponent(firstName)
        var copyNumber = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) copy \(copyNumber)\(suffix)")
            copyNumber += 1
        }
        return candidate
    }
}

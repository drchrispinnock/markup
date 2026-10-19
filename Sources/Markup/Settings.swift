import Foundation

/// App-wide settings, kept in user defaults.
@MainActor
final class Settings {
    static let shared = Settings(defaults: .standard)

    static let imagesDirectoryKey = "MarkupImagesDirectory"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The first folder to look in for a document's images. Nil if none is
    /// set.
    var imagesDirectory: URL? {
        get {
            defaults.string(forKey: Self.imagesDirectoryKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            defaults.set(newValue?.path, forKey: Self.imagesDirectoryKey)
        }
    }

    /// The folders an image's path is looked up in, in order: the images
    /// directory, then the document's own folder, then its `resources` and
    /// `images` subfolders.
    func imageFolders(forDocumentAt documentURL: URL?) -> [URL] {
        let folder = documentURL?.deletingLastPathComponent()
        return [imagesDirectory, folder, folder?.appendingPathComponent("resources", isDirectory: true),
                folder?.appendingPathComponent("images", isDirectory: true)].compactMap { $0 }
    }
}

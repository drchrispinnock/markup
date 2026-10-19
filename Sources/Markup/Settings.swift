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

    /// A folder to look in for a document's images, after the document's own
    /// folder. Nil if none is set.
    var imagesDirectory: URL? {
        get {
            defaults.string(forKey: Self.imagesDirectoryKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            defaults.set(newValue?.path, forKey: Self.imagesDirectoryKey)
        }
    }
}

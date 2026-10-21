import AppKit
import Sparkle

/// Software updates, with Sparkle. It reads the feed (`SUFeedURL`) and the
/// key updates are signed with (`SUPublicEDKey`) from Info.plist, and asks
/// at the second launch whether to check automatically.
///
/// Sparkle updates an app bundle in place, so a bare executable (`swift run`,
/// tests) has no updater and Check for Updates is disabled. Nor is there one
/// without a key: Sparkle would fail to start, with an alert at every launch.
@MainActor
final class Updater: NSObject {
    private let controller: SPUStandardUpdaterController?

    override init() {
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        let hasKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.isEmpty == false
        controller = isAppBundle && hasKey ? SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil) : nil
        super.init()
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var browser: DocumentBrowserViewController? { window?.rootViewController as? DocumentBrowserViewController }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = DocumentBrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
        open(connectionOptions.urlContexts)
        #if DEBUG
        // `-open <path>` opens a file at launch, for trying the editor in
        // the simulator: `xcrun simctl launch booted com.chrispinnock.MarkupGo -open <path>`.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-open"), index + 1 < arguments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.browser?.open(URL(fileURLWithPath: arguments[index + 1]))
            }
        }
        #endif
    }

    /// A file opened from Files or another app.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url, url.isFileURL, let browser else { return }
        browser.revealDocument(at: url, importIfNeeded: true) { revealed, _ in
            MainActor.assumeIsolated {
                if let revealed { browser.open(revealed) }
            }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Save now, rather than at the next autosave.
        let editor = (browser?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorViewController
        if let file = editor?.file, file.hasUnsavedChanges { file.autosave(completionHandler: nil) }
    }
}

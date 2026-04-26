import Cocoa

/// Tiny windowed wrapper that hosts every registered DemoScene in an NSWindow,
/// with a "Scene" menu listing all scenes and "File → Save Frame…" to capture
/// the current view to a PNG. Built for screenshot-grabbing and dev iteration
/// without going through ScreenSaverEngine.
@main
final class DemoApp: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var window: NSWindow!
    private var view: DemoView!
    private var sceneMenuItems: [NSMenuItem] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = DemoApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Nerdymark Screensaver — Demo"
        window.delegate = self
        window.center()

        view = DemoView(frame: frame)
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        buildMenu()
        updateMenuChecks()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Nerdymark Demo",
                                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                    keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide",
                                    action: #selector(NSApplication.hide(_:)),
                                    keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit",
                                    action: #selector(NSApplication.terminate(_:)),
                                    keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Save Frame…",
                                     action: #selector(saveFrame(_:)),
                                     keyEquivalent: "s"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Scene menu — populated from SceneRegistry.
        let sceneItem = NSMenuItem(title: "Scene", action: nil, keyEquivalent: "")
        let sceneMenu = NSMenu(title: "Scene")
        sceneMenuItems.removeAll()
        for sceneType in SceneRegistry.allScenes {
            let item = NSMenuItem(title: sceneType.displayName,
                                  action: #selector(switchScene(_:)),
                                  keyEquivalent: "")
            item.representedObject = sceneType.identifier
            item.target = self
            sceneMenu.addItem(item)
            sceneMenuItems.append(item)
        }
        sceneItem.submenu = sceneMenu
        mainMenu.addItem(sceneItem)

        // Window menu
        let winItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(NSMenuItem(title: "Minimize",
                                    action: #selector(NSWindow.miniaturize(_:)),
                                    keyEquivalent: "m"))
        winMenu.addItem(NSMenuItem(title: "Zoom",
                                    action: #selector(NSWindow.performZoom(_:)),
                                    keyEquivalent: ""))
        winItem.submenu = winMenu
        mainMenu.addItem(winItem)

        NSApp.mainMenu = mainMenu
    }

    private func updateMenuChecks() {
        let currentId = view.currentSceneType?.identifier
        for item in sceneMenuItems {
            item.state = (item.representedObject as? String) == currentId ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func switchScene(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let sceneType = SceneRegistry.scene(for: id) else { return }
        view.select(sceneType)
        updateMenuChecks()
        window.title = "Nerdymark Screensaver — \(sceneType.displayName)"
    }

    @objc private func saveFrame(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["png"]
        let safeName = (view.currentSceneType?.identifier ?? "frame")
            .replacingOccurrences(of: "_", with: "-")
        panel.nameFieldStringValue = "saver-\(safeName).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}

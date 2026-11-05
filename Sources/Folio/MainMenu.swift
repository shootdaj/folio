import AppKit
import FolioCore

/// The main menu, built in code (no nib).
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let name = "Folio"
        let main = NSMenu()

        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services

        add(name, to: main, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            servicesItem,
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", to: main, [
            item("New Window", #selector(AppDelegate.newWindow(_:)), "n"),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])
        // File commands go to the window controller; while a name or the address is being edited the
        // text field takes Cut, Copy, Paste and Select All, and Undo and Redo undo the typing.
        add("Edit", to: main, [
            item("Undo", #selector(BrowserWindowController.undoOperation(_:)), "z"),
            item("Redo", #selector(BrowserWindowController.redoOperation(_:)), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Copy To...", #selector(BrowserWindowController.copyTo(_:))),
            item("Move To...", #selector(BrowserWindowController.moveTo(_:))),
            .separator(),
            item("Rename", #selector(BrowserWindowController.renameSelection(_:)), key(NSF2FunctionKey), []),
            item("Move to Trash", #selector(BrowserWindowController.moveToTrash(_:)), "\u{8}"),
            item("Delete Permanently...", #selector(BrowserWindowController.deletePermanently(_:)), "\u{8}", [.command, .option]),
            submenu("New", newItems()),
            .separator(),
            item("Select All", #selector(NSResponder.selectAll(_:)), "a"),
            item("Select None", #selector(BrowserWindowController.selectNone(_:))),
            item("Invert Selection", #selector(BrowserWindowController.invertSelection(_:))),
        ])
        add("View", to: main, [
            submenu("Theme", ThemeChoice.allCases.map {
                choice($0.title, #selector(AppDelegate.selectTheme(_:)), $0.rawValue)
            }),
            submenu("Accent", AccentChoice.allCases.map {
                choice($0.title, #selector(AppDelegate.selectAccent(_:)), $0.rawValue)
            }),
            .separator(),
            item("Item Check Boxes", #selector(BrowserWindowController.toggleItemCheckBoxes(_:))),
            submenu("Sort By", sortItems()),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        // Finder shortcuts here; Option+arrows (Anshul's Karabiner-swapped Cmd) live in BrowserWindow.
        add("Go", to: main, [
            item("Back", #selector(BrowserWindowController.goBack(_:)), "["),
            item("Forward", #selector(BrowserWindowController.goForward(_:)), "]"),
            item("Up", #selector(BrowserWindowController.goUp(_:)), key(NSUpArrowFunctionKey)),
            item("Home", #selector(BrowserWindowController.goHome(_:)), "h", [.command, .shift]),
            item("Refresh", #selector(BrowserWindowController.refresh(_:)), key(NSF5FunctionKey), []),
            .separator(),
            // Anshul's Cmd+D reaches the app as Option+D (bound in BrowserWindow) or, via BTT, as Cmd+L.
            item("Edit Address", #selector(BrowserWindowController.focusAddressBar(_:)), "l"),
            item("Address History", #selector(BrowserWindowController.showAddressHistory(_:)), key(NSF4FunctionKey), []),
            item("Copy Address", #selector(BrowserWindowController.copyAddress(_:))),
            item("Copy Address as Text", #selector(BrowserWindowController.copyAddressAsText(_:))),
        ])
        let window = add("Window", to: main, [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        return main
    }

    /// Edit > New and the command bar's New: Folder (Explorer's Ctrl+Shift+N) and Text document.
    static func newItems() -> [NSMenuItem] {
        [item("Folder", #selector(BrowserWindowController.newFolder(_:)), "n", [.command, .shift]),
         item("Text Document", #selector(BrowserWindowController.newTextDocument(_:)))]
    }

    static func sortItems() -> [NSMenuItem] {
        var items = SortKey.allCases.map { key in
            choice(sortTitle(key), #selector(BrowserWindowController.sortByColumn(_:)), key.rawValue)
        }
        items.append(.separator())
        items.append(item("Ascending", #selector(BrowserWindowController.sortAscending(_:))))
        items.append(item("Descending", #selector(BrowserWindowController.sortDescending(_:))))
        return items
    }

    private static func sortTitle(_ key: SortKey) -> String {
        switch key {
        case .name: "Name"
        case .modified: "Date modified"
        case .kind: "Type"
        case .size: "Size"
        }
    }

    @discardableResult
    private static func add(_ title: String, to main: NSMenu, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    /// A ticked choice; the AppDelegate validates which one is on.
    private static func choice(_ title: String, _ action: Selector, _ value: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = value
        return item
    }

    private static func key(_ functionKey: Int) -> String {
        String(utf16CodeUnits: [unichar(functionKey)], count: 1)
    }
}

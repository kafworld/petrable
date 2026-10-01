import SwiftUI

#if os(macOS)
import AppKit
#endif

enum Clipboard {
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }

    static func pasteText() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }
}

extension View {
    @ViewBuilder
    func hiddenNavigationBarWhenAvailable() -> some View {
        #if os(macOS)
        self
        #else
        self.toolbar(.hidden, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    func keyboardDismissModeWhenAvailable() -> some View {
        #if os(macOS)
        self
        #else
        self.scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    func darkNavigationChromeWhenAvailable() -> some View {
        #if os(macOS)
        self
            // Match the iOS navy nav bar: the sheet's titlebar strip paints
            // hero navy instead of neutral window grey (bottom chrome is
            // window background — handled by navySheetChrome).
            .toolbarBackground(Theme.hero, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
            .navySheetChrome()
        #else
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.hero, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    /// Main window: same navy titlebar treatment (keeps the drag strip).
    @ViewBuilder
    func mainWindowChrome() -> some View {
        #if os(macOS)
        self
            .toolbarBackground(Theme.hero, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarColorScheme(.dark, for: .windowToolbar)
            .onAppear { NavySheetPainter.apply() }   // installs the window observer
        #else
        self
        #endif
    }

    /// Navy toolbar background applied INSIDE a NavigationStack (on the
    /// content) — applying it on the stack itself doesn't reach a sheet's
    /// toolbar, which then falls back to the neutral material.
    @ViewBuilder
    func navyToolbarBackground() -> some View {
        #if os(macOS)
        self
            .toolbarBackground(Theme.hero, for: .windowToolbar, .automatic)
            .toolbarBackground(.visible, for: .windowToolbar, .automatic)
            .toolbarColorScheme(.dark, for: .windowToolbar, .automatic)
        #else
        self
        #endif
    }

    /// A macOS sheet's native titlebar/bottom chrome ignores SwiftUI toolbar
    /// modifiers — repaint the sheet panel itself hero navy via AppKit.
    /// Does NOT rely on `isSheet` (SwiftUI sheets are not always flagged);
    /// matches any visible titled window narrower than the main window and
    /// re-applies while the sheet settles.
    @ViewBuilder
    func navySheetChrome() -> some View {
        #if os(macOS)
        self.onAppear {
            NavySheetPainter.apply()
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func previewPresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        self.sheet(isPresented: isPresented) {
            content()
                .frame(minWidth: 980, idealWidth: 1100, minHeight: 720, idealHeight: 780)
        }
        #else
        self.fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func desktopSheetFrame(width: CGFloat = 860, height: CGFloat = 680) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Repaints secondary macOS windows (sheets such as Tool connections /
/// Details) so their native titlebar and bottom chrome read as the app's
/// hero navy instead of neutral window grey.
enum NavySheetPainter {
    private static let navy = NSColor(red: 11/255, green: 17/255, blue: 31/255, alpha: 1)

    static func apply() {
        installObserver()
        patch()
        // The sheet window finishes animating/resizing after onAppear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { patch() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { patch() }
    }

    private static var observer: NSObjectProtocol?
    private static func installObserver() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let w = note.object as? NSWindow, w.isVisible, w.frame.width < 1000 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                patch(window: w)
                log("become-key patch for title='\(w.title ?? "")'")
            }
        }
    }

    private static func patch() {
        for w in NSApp.windows {
            patch(window: w)
        }
    }

    private static func patch(window w: NSWindow) {
        guard w.isVisible, w.frame.width < 1000 else {
            log("skip title='\(w.title ?? "")' frame=\(w.frame) sheet=\(w.isSheet)")
            return
        }
        w.titlebarAppearsTransparent = true
        w.backgroundColor = navy
        if !w.styleMask.contains(.fullSizeContentView) {
            w.styleMask.insert(.fullSizeContentView)
        }
        if let root = w.contentView?.superview {
            // The whole-sheet NSVisualEffectView backdrop is what renders the
            // neutral grey behind SwiftUI's transparent top/bottom chrome.
            for sub in root.subviews {
                if let effect = sub as? NSVisualEffectView {
                    effect.isHidden = true
                    log("hid window backdrop NSVisualEffectView frame=\(effect.frame)")
                }
            }
            hideTitlebarMaterial(in: root)
            if !dumped.contains(w.windowNumber) {
                dumped.insert(w.windowNumber)
                dumpHierarchy(root, depth: 0)
            }
        } else {
            log("no contentview.superview for '\(w.title ?? "")'")
        }
        log("patched title='\(w.title ?? "")' frame=\(w.frame) style=\(w.styleMask.rawValue)")
    }

    private static var dumped = Set<Int>()

    private static func dumpHierarchy(_ view: NSView, depth: Int) {
        guard depth < 10 else { return }
        let cls = String(describing: type(of: view))
        let interesting = cls.contains("Titlebar") || cls.contains("Toolbar")
            || cls.contains("Effect") || cls.contains("Background")
            || cls.contains("Separator") || depth < 3
        if interesting && !view.isHidden {
            let f = view.frame
            log(String(format: "%@%@ d=%d frame=(%.0f,%.0f,%.0f,%.0f) alpha=%.2f bg=%@",
                       String(repeating: "  ", count: depth), cls, depth,
                       f.origin.x, f.origin.y, f.size.width, f.size.height,
                       view.alphaValue,
                       view.layer?.backgroundColor.map { String(describing: $0) } ?? "nil"))
        }
        for sub in view.subviews {
            dumpHierarchy(sub, depth: depth + 1)
        }
    }

    private static func log(_ message: String) {
        let line = "[navy] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = "/tmp/navy.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
        print(line, terminator: "")
    }

    /// Walk the window hierarchy: paint every titlebar/toolbar container navy
    /// and hide the NSVisualEffectView material that renders neutral grey.
    private static func hideTitlebarMaterial(in view: NSView) {
        let cls = String(describing: type(of: view))
        if cls.contains("NSTitlebarContainerView") || cls.contains("NSToolbarContainerView") {
            view.wantsLayer = true
            view.layer?.backgroundColor = navy.cgColor
            for sub in view.subviews {
                let subCls = String(describing: type(of: sub))
                if subCls.contains("Background") || sub is NSVisualEffectView {
                    sub.isHidden = true
                    log("hid material \(subCls) in \(cls)")
                }
            }
        }
        for sub in view.subviews {
            hideTitlebarMaterial(in: sub)
        }
    }
}
#endif

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
        #else
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.hero, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

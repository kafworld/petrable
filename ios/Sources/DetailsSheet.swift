import SwiftUI

/// "Details" for a build: the generated files, tap into any to read the code.
struct DetailsSheet: View {
    @ObservedObject var vm: ProjectViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if vm.files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.textSecondary)
                        Text("No files yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(vm.files) { file in
                                NavigationLink {
                                    CodeDetailView(file: file)
                                } label: {
                                    fileRow(file)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(vm.project.map { "\($0.name) · Files" } ?? "Files")
            .darkNavigationChromeWhenAvailable()
        }
        .desktopSheetFrame()
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func fileRow(_ file: ProjectFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.blue)
                .frame(width: 38, height: 38)
                .background(Theme.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(file.language) · \(file.lineCount) lines")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CodeDetailView: View {
    let file: ProjectFile

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView([.vertical, .horizontal]) {
                Text(file.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(file.path)
        .darkNavigationChromeWhenAvailable()
    }
}

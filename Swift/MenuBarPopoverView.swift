import SwiftUI

// MARK: - View model (owned by AppDelegate, observed by the view)

class PopoverViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var hotkeyDisplay: String = "⌥L"

    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenHistory: (() -> Void)?

    func toggleRecording() {
        if isRecording { onStopRecording?() } else { onStartRecording?() }
    }
}

// MARK: - View

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(spacing: 2) {
            ToolButton(
                icon: viewModel.isRecording ? "stop.fill" : "mic",
                tint: viewModel.isRecording ? recordingTint : Color.textPrimary(for: scheme),
                tooltip: viewModel.isRecording
                    ? "Stop recording  \(viewModel.hotkeyDisplay)"
                    : "Start recording  \(viewModel.hotkeyDisplay)",
                scheme: scheme,
                action: viewModel.toggleRecording
            )
            divider
            ToolButton(
                icon: "list.bullet.rectangle",
                tint: Color.textPrimary(for: scheme),
                tooltip: "History",
                scheme: scheme,
                action: { viewModel.onOpenHistory?() }
            )
            ToolButton(
                icon: "gearshape",
                tint: Color.textPrimary(for: scheme),
                tooltip: "Settings  ⌘,",
                scheme: scheme,
                action: { viewModel.onOpenSettings?() }
            )
            divider
            ToolButton(
                icon: "power",
                tint: Color.textPrimary(for: scheme),
                tooltip: "Quit uttr  ⌘Q",
                scheme: scheme,
                action: { NSApplication.shared.terminate(nil) }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: 220)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.rowSeparator(for: scheme))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var recordingTint: Color {
        scheme == .dark ? Color(hex: 0xE07060) : Color(hex: 0xB94A3D)
    }
}

private struct ToolButton: View {
    let icon: String
    let tint: Color
    let tooltip: String
    let scheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.textPrimary(for: scheme).opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    let vm = PopoverViewModel()
    return MenuBarPopoverView(viewModel: vm)
}

import SwiftUI
import XeneonKit

/// The menu bar popover: the everyday controls for one display.
struct MenuContent: View {
    @Bindable var app: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let model = app.selected {
                DisplayQuickControls(model: model)
                snapshotMenu(for: model)
            } else {
                Text("No external display connected.")
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 340)
        .task(id: app.selected?.id) { await app.selected?.refresh() }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if app.displays.count > 1 {
                Picker("Display", selection: Binding(get: { app.selected?.id }, set: { app.selectedID = $0 })) {
                    ForEach(app.displays) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text(app.selected?.name ?? "Xeneon Control").font(.headline)
            }
            Spacer(minLength: 12)
            if let model = app.selected { LinkBadge(link: model.link) }
        }
    }

    @ViewBuilder private func snapshotMenu(for model: DisplayModel) -> some View {
        let saved = app.snapshots(for: model)
        if !saved.isEmpty {
            Menu("Apply Snapshot") {
                ForEach(saved) { snapshot in
                    Button(snapshot.name) { app.apply(snapshot) }
                }
            }
            .fixedSize()
        }
    }
}

struct DisplayQuickControls: View {
    let model: DisplayModel
    @State private var showsBalance = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.link {
            case .probing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Talking to the display…").foregroundStyle(.secondary)
                }
            case .hardware:
                if model.supports(.brightness) {
                    VCPSlider(model: model, code: .brightness, title: "Brightness", systemImage: "sun.max")
                }
                if model.supports(.contrast) {
                    VCPSlider(model: model, code: .contrast, title: "Contrast", systemImage: "circle.lefthalf.filled")
                }
                if model.supports(.colorPreset) { PresetPicker(model: model) }
                if model.supports(.colorTemperatureRequest), !model.isUserPresetActive { TemperatureSlider(model: model) }
                if Self.hasGains(model) {
                    DisclosureGroup("Colour balance", isExpanded: $showsBalance) {
                        GainSliders(model: model).padding(.top, 8)
                    }
                }
            case .softwareOnly:
                Text("This connection doesn't carry DDC/CI, so the monitor can't be adjusted directly. These controls change the picture in the GPU instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SoftwareSliders(model: model)
            }
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    static func hasGains(_ model: DisplayModel) -> Bool {
        DisplayModel.gainCodes.allSatisfy(model.supports)
    }
}

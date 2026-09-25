import SwiftUI
import XeneonKit

/// The menu bar popover: the everyday controls for one display.
struct MenuContent: View {
    @Bindable var app: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let model = app.selected {
                DisplayQuickControls(model: model)
                RestoreButtons(model: model)
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
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(FitWindowToContent(height: contentHeight))
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
    @Bindable var model: DisplayModel
    @AppStorage("showsColourBalance") private var showsBalance = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.link {
            case .probing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the display's current settings…").foregroundStyle(.secondary)
                }
            case .hardware:
                ControlSourceHeader(source: .monitor)
                if model.supports(.brightness) {
                    VCPSlider(model: model, code: .brightness, title: "Brightness", systemImage: "sun.max")
                }
                if model.supports(.contrast) {
                    VCPSlider(model: model, code: .contrast, title: "Contrast", systemImage: "circle.lefthalf.filled")
                }
                if model.supports(.colorPreset) {
                    PresetPicker(model: model)
                    if !model.hardwareWhitePoints.isEmpty { HardwareWhitePointPicker(model: model) }
                }
                Divider()
                ControlSourceHeader(source: .gpu)
                GPUAdjustments(model: model) {
                    WhitePointSlider(model: model)
                    GammaSlider(model: model)
                    DisclosureGroup("Colour balance", isExpanded: $showsBalance) {
                        SoftwareBalanceSliders(model: model).padding(.top, 8)
                    }
                }
            case .softwareOnly:
                Text("This connection doesn't carry DDC/CI, so the monitor's own settings can't be reached. Only GPU adjustments are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ControlSourceHeader(source: .gpu)
                GPUAdjustments(model: model) { SoftwareSliders(model: model) }
            }
            if let message = model.message { NoticeLabel(notice: message).font(.caption) }
        }
    }

    static func hasGains(_ model: DisplayModel) -> Bool {
        DisplayModel.gainCodes.allSatisfy(model.supports)
    }
}

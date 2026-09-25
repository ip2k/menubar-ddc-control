import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import XeneonKit

struct SettingsView: View {
    @Bindable var app: AppModel

    var body: some View {
        TabView {
            DisplaysPane(app: app)
                .tabItem { Label("Displays", systemImage: "display") }
            SnapshotsPane(app: app)
                .tabItem { Label("Snapshots", systemImage: "camera.filters") }
            GeneralPane(app: app)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

// MARK: Displays

struct DisplaysPane: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { app.selected?.id }, set: { app.selectedID = $0 })) {
                ForEach(app.displays) { model in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.name)
                        LinkBadge(link: model.link)
                    }
                    .padding(.vertical, 3)
                    .tag(Optional(model.id))
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            Divider()
            if let model = app.selected {
                DisplayDetail(app: app, model: model)
            } else {
                ContentUnavailableView("No External Display", systemImage: "display.trianglebadge.exclamationmark",
                                       description: Text("Connect a monitor to adjust it here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct DisplayDetail: View {
    let app: AppModel
    let model: DisplayModel
    @State private var confirmsFactoryReset = false
    @State private var importsProfile = false

    var body: some View {
        Form {
            if let message = model.message {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            switch model.link {
            case .probing:
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the display's capabilities…")
                    }
                }
            case .hardware:
                hardwareSections
            case .softwareOnly:
                Section {
                    Text("This connection doesn't carry DDC/CI, so the monitor's own settings can't be reached. On M1-generation MacBook Pros the built-in HDMI port never passes DDC/CI; connect over USB-C or DisplayPort to use hardware controls.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Hardware controls unavailable")
                }
            }
            profileSection
            Section {
                SoftwareSliders(model: model)
            } header: {
                Text("Software adjustment (GPU)")
            } footer: {
                FooterText("Scales the picture on top of the colour profile's calibration. It works on any connection and can dim below the backlight's minimum, but costs contrast, and it lasts only while Xeneon Control is running.")
            }
            if model.link == .hardware, [.restoreColorDefaults, .restoreBrightnessContrast, .restoreFactoryDefaults].contains(where: model.advertises) {
                resetSection
            }
            infoSection
        }
        .formStyle(.grouped)
        .task(id: model.id) { await model.refresh() }
        .fileImporter(isPresented: $importsProfile, allowedContentTypes: [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                app.importProfile(from: url, for: model)
            }
        }
    }

    @ViewBuilder private var hardwareSections: some View {
        Section("Picture") {
            if model.supports(.brightness) {
                VCPSlider(model: model, code: .brightness, title: "Brightness", systemImage: "sun.max")
            }
            if model.supports(.contrast) {
                VCPSlider(model: model, code: .contrast, title: "Contrast", systemImage: "circle.lefthalf.filled")
            }
            if model.supports(.sharpness) {
                VCPSlider(model: model, code: .sharpness, title: "Sharpness", systemImage: "rhombus")
            }
        }
        Section {
            if model.supports(.colorPreset) { PresetPicker(model: model) }
            if model.supports(.colorTemperatureRequest) { TemperatureSlider(model: model) }
            if DisplayQuickControls.hasGains(model) { GainSliders(model: model) }
        } header: {
            Text("Colour")
        } footer: {
            FooterText("RGB gains set the white point in the monitor itself, before any colour profile. To calibrate, set the gains here first, then profile the display with your colorimeter.")
        }
        if model.supports(.osdLanguage), let languages = model.capabilities?.vcp[.osdLanguage], !languages.isEmpty {
            Section("On-screen menu") {
                Picker("Language", selection: Binding(
                    get: { UInt8(clamping: model.value(.osdLanguage)) },
                    set: { model.set(.osdLanguage, Int($0)) }
                )) {
                    ForEach(languages, id: \.self) { Text(VCPNames.osdLanguage($0)).tag($0) }
                }
            }
        }
    }

    @ViewBuilder private var profileSection: some View {
        let groups = app.profileGroups(for: model)
        Section {
            Picker("Profile", selection: Binding(
                get: { model.profile?.url },
                set: { url in
                    guard let url, url != model.profile?.url else { return }
                    app.assign(app.profiles.first { $0.url == url } ?? ICCProfile(url: url, name: ""), to: model)
                }
            )) {
                if !groups.matching.isEmpty {
                    Section("For this display") {
                        ForEach(groups.matching) { Text($0.name).tag(Optional($0.url)) }
                    }
                }
                Section("Other profiles") {
                    ForEach(groups.other) { Text($0.name).tag(Optional($0.url)) }
                }
            }
            HStack {
                Button("Import Profile…") { importsProfile = true }
                Button("Use Factory Profile") { app.assign(nil, to: model) }
                Spacer()
                Button("Open ColorSync Utility") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/ColorSync Utility.app"))
                }
            }
        } header: {
            Text("Colour profile (ICC)")
        } footer: {
            if let path = model.profile?.url.path {
                FooterText(path).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var resetSection: some View {
        Section("Reset") {
            HStack {
                if model.advertises(.restoreColorDefaults) {
                    Button("Restore Colour Defaults") { model.restore(.restoreColorDefaults) }
                }
                if model.advertises(.restoreBrightnessContrast) {
                    Button("Restore Brightness & Contrast") { model.restore(.restoreBrightnessContrast) }
                }
                Spacer()
                if model.advertises(.restoreFactoryDefaults) {
                    Button("Factory Reset…", role: .destructive) { confirmsFactoryReset = true }
                }
            }
            .confirmationDialog("Reset \(model.name) to factory settings?", isPresented: $confirmsFactoryReset) {
                Button("Factory Reset", role: .destructive) { model.restore(.restoreFactoryDefaults) }
            } message: {
                Text("Every setting in the monitor's on-screen menu returns to its default.")
            }
        }
    }

    @ViewBuilder private var infoSection: some View {
        Section("Information") {
            LabeledContent("Manufacturer", value: "\(model.display.identity.manufacturerID) (\(model.display.identity.vendor))")
            LabeledContent("Model / serial", value: "\(model.display.identity.model) / \(model.display.identity.serial)")
            if let caps = model.capabilities {
                LabeledContent("Controller", value: [caps.model, caps.fields["type"]].compactMap { $0 }.joined(separator: ", "))
                LabeledContent("MCCS version", value: caps.mccsVersion ?? "—")
            }
            if let refresh = model.info[.verticalFrequency] {
                LabeledContent("Refresh rate", value: String(format: "%.2f Hz", Double(refresh.current) / 100))
            }
            if let technology = model.info[.displayTechnology] {
                LabeledContent("Panel", value: VCPNames.displayTechnology(technology.current))
            }
            if let caps = model.capabilities, !caps.raw.isEmpty {
                DisclosureGroup("Capabilities string") {
                    Text(caps.raw)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: Snapshots

struct SnapshotsPane: View {
    @Bindable var app: AppModel
    @State private var newName = ""

    var body: some View {
        Form {
            if let model = app.selected {
                Section {
                    HStack {
                        TextField("Name", text: $newName, prompt: Text("Evening, Photo editing…"))
                        Button("Save Current Settings") {
                            app.saveSnapshot(named: newName.trimmingCharacters(in: .whitespaces), of: model)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("New snapshot of \(model.name)")
                } footer: {
                    FooterText("A snapshot records the monitor's preset, white point, gains, brightness, contrast and sharpness, plus the software adjustment and colour profile.")
                }
            }
            Section("Saved") {
                if app.snapshots.isEmpty {
                    Text("No snapshots yet.").foregroundStyle(.secondary)
                }
                ForEach(app.snapshots) { snapshot in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.name)
                            Text(snapshot.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apply") { app.apply(snapshot) }
                            .disabled(!app.displays.contains { $0.id == snapshot.displayKey })
                        Button(role: .destructive) {
                            app.snapshots.removeAll { $0.id == snapshot.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(snapshot.name)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: General

struct GeneralPane: View {
    let app: AppModel
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchesAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            } footer: {
                FooterText("Software adjustments only apply while the app runs, so opening it at login keeps them in place.")
            }
            Section {
                Button("Rescan Displays") { app.rescan() }
                Button("Reload Colour Profiles") { app.reloadProfiles() }
            }
        }
        .formStyle(.grouped)
    }
}

/// Section footer text, leading-aligned: grouped forms otherwise right-align wrapped footers.
struct FooterText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

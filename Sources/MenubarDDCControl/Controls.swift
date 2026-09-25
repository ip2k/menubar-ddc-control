import SwiftUI
import DDCKit

/// A labelled slider with its value on the title row, clear of the track.
struct ValueSlider<Accessory: View>: View {
    let title: String
    var systemImage: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Values snap to multiples of this. Applied in the binding rather than as the slider's
    /// `step`, which on macOS draws a tick mark per step.
    var step: Double = 1
    var tint: Color?
    var format: (Double) -> String = { String(Int($0.rounded())) }
    /// Shown under the track, e.g. reference markers.
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer(minLength: 12)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .font(.callout)
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .tint(tint)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
            accessory()
        }
    }
}

extension ValueSlider where Accessory == EmptyView {
    init(title: String, systemImage: String? = nil, value: Binding<Double>, range: ClosedRange<Double>,
         step: Double = 1, tint: Color? = nil, format: @escaping (Double) -> String = { String(Int($0.rounded())) }) {
        self.init(title: title, systemImage: systemImage, value: value, range: range, step: step, tint: tint,
                  format: format, accessory: { EmptyView() })
    }
}

/// Hardware slider bound to a VCP code, using the monitor's own maximum.
struct VCPSlider: View {
    let model: DisplayModel
    let code: VCPCode
    let title: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        ValueSlider(title: title, systemImage: systemImage, value: model.binding(code),
                    range: 0...Double(model.maximum(code)), tint: tint)
            .disabled(!model.canWrite)
    }
}

/// Fine white point in 10 K steps, applied on the GPU relative to the preset's own white,
/// with the CIE daylight illuminants marked under the track (tap one to snap to it).
struct WhitePointSlider: View {
    @Bindable var model: DisplayModel

    var body: some View {
        ValueSlider(title: "Fine white point", systemImage: "thermometer.medium", value: $model.software.whitePoint,
                    range: WhitePoint.range, step: WhitePoint.step, format: { "\(Int($0.rounded())) K" }) {
            MarkerRow(range: WhitePoint.range, markers: WhitePoint.markers) { model.software.whitePoint = $0 }
        }
    }
}

struct MarkerRow: View {
    let range: ClosedRange<Double>
    let markers: [(name: String, kelvin: Double)]
    let select: (Double) -> Void
    /// Horizontal distance from the slider's edge to the centre of its knob at either end.
    private let trackInset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - 2 * trackInset
            ForEach(markers, id: \.name) { marker in
                let fraction = (marker.kelvin - range.lowerBound) / (range.upperBound - range.lowerBound)
                let x = trackInset + usable * fraction
                // Keep each label inside the row even where its tick sits near an edge.
                let labelX = min(max(x, 14), geo.size.width - 14)
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1, height: 4)
                    .position(x: x, y: 2)
                Button(marker.name) { select(marker.kelvin) }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: labelX, y: 13)
                    .help("\(marker.name): \(Int(marker.kelvin)) K")
            }
        }
        .frame(height: 20)
    }
}

struct GammaSlider: View {
    @Bindable var model: DisplayModel

    var body: some View {
        ValueSlider(title: "Gamma", systemImage: "circle.bottomrighthalf.pattern.checkered", value: $model.software.gamma,
                    range: SoftwareAdjustment.gammaRange, step: 0.01, format: { String(format: "%.2f", $0) })
    }
}

struct PresetPicker: View {
    let model: DisplayModel

    var body: some View {
        let presets = model.capabilities?.vcp[.colorPreset] ?? []
        let current = UInt8(clamping: model.value(.colorPreset))
        VStack(alignment: .leading, spacing: 6) {
            Picker("Colour preset", selection: Binding(get: { current }, set: { model.set(.colorPreset, Int($0)) })) {
                ForEach(presets, id: \.self) { Text(VCPNames.colorPreset($0)).tag($0) }
                if !presets.contains(current) {
                    Text(VCPNames.colorPreset(current)).tag(current)
                }
            }
            .disabled(!model.canWrite)
            if model.display.quirks.leavingUserPresetResetsGains, model.isUserPresetActive {
                Text("On this monitor some presets (sRGB, Native) can reset \(VCPNames.colorPreset(current))'s factory calibration. Switching back to \(VCPNames.colorPreset(current)) restores it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The monitor's own RGB gains. Read-only when the monitor ignores writes to them.
struct GainSliders: View {
    let model: DisplayModel

    var body: some View {
        let locked = DisplayModel.gainCodes.allSatisfy(model.ignoredCodes.contains)
        VStack(alignment: .leading, spacing: 10) {
            if locked {
                LabeledContent("Red / Green / Blue gain") {
                    Text(DisplayModel.gainCodes.map { String(model.value($0)) }.joined(separator: " / "))
                        .monospacedDigit()
                        .padding(.leading, 12)
                }
                Text("This monitor keeps its factory-calibrated gains and ignores changes to them over DDC/CI. For finer control, tick Adjust colors using GPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VCPSlider(model: model, code: .redGain, title: "Red gain", tint: .red)
                VCPSlider(model: model, code: .greenGain, title: "Green gain", tint: .green)
                VCPSlider(model: model, code: .blueGain, title: "Blue gain", tint: .blue)
            }
        }
    }
}

/// GPU colour balance and brightness. White point and gamma are separate controls.
struct SoftwareBalanceSliders: View {
    @Bindable var model: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ValueSlider(title: "Red", value: $model.software.red, range: SoftwareAdjustment.gainRange, step: 0.01,
                        tint: .red, format: Self.percent)
            ValueSlider(title: "Green", value: $model.software.green, range: SoftwareAdjustment.gainRange, step: 0.01,
                        tint: .green, format: Self.percent)
            ValueSlider(title: "Blue", value: $model.software.blue, range: SoftwareAdjustment.gainRange, step: 0.01,
                        tint: .blue, format: Self.percent)
        }
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}

struct SoftwareSliders: View {
    @Bindable var model: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ValueSlider(title: "Brightness", systemImage: "sun.min", value: $model.software.brightness,
                        range: SoftwareAdjustment.brightnessRange, step: 0.01, format: SoftwareBalanceSliders.percent)
            WhitePointSlider(model: model)
            GammaSlider(model: model)
            SoftwareBalanceSliders(model: model)
            Button("Reset GPU Adjustments") { model.resetGPUValues() }
                .disabled(model.software.valuesAreDefault)
        }
    }
}

/// The monitor's own white points: its colour-temperature presets, chosen from a menu because
/// there are only a few (four on the Xeneon Edge). Selecting one switches the monitor's preset.
struct HardwareWhitePointPicker: View {
    let model: DisplayModel

    var body: some View {
        let steps = model.hardwareWhitePoints
        let current = UInt8(clamping: model.value(.colorPreset))
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: Binding(get: { current }, set: { model.set(.colorPreset, Int($0)) })) {
                ForEach(steps, id: \.preset) { step in
                    Text(verbatim: "\(step.kelvin) K").tag(step.preset)
                }
                if !steps.contains(where: { $0.preset == current }) {
                    Divider()
                    Text(verbatim: Self.otherPresetTitle(current, kelvin: model.presetKelvin)).tag(current)
                }
            } label: {
                Label("White point", systemImage: "thermometer.medium")
            }
            .pickerStyle(.menu)
            .disabled(!model.canWrite)
            Text(Self.caption(for: model, steps: steps.map(\.kelvin)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func otherPresetTitle(_ preset: UInt8, kelvin: Int?) -> String {
        let name = VCPNames.colorPreset(preset)
        guard let kelvin, VCPNames.isUserPreset(preset) else { return name }
        return "\(name) (\(kelvin) K, calibrated)"
    }

    static func caption(for model: DisplayModel, steps: [Int]) -> String {
        let list = ListFormatter.localizedString(byJoining: steps.map { "\($0) K" })
        let who = model.display.isXeneonEdge ? "The Xeneon Edge" : "This monitor"
        let count = NumberFormatter.localizedString(from: steps.count as NSNumber, number: .spellOut)
        return "\(who) has only \(count) built-in white-point calibrations (\(list)). For anything in between, tick Adjust colors using GPU."
    }
}

/// A section title that says where its controls take effect.
struct ControlSourceHeader: View {
    enum Source { case monitor, gpu }
    let source: Source

    var body: some View {
        switch source {
        case .monitor:
            Label("Monitor (DDC/CI)", systemImage: "cable.connector")
                .font(.subheadline.weight(.semibold))
                .help("Settings stored in the monitor itself")
        case .gpu:
            Label("GPU", systemImage: "cpu")
                .font(.subheadline.weight(.semibold))
                .help("Applied by the graphics card on top of the monitor and its colour profile")
        }
    }
}

/// The opt-in checkbox for GPU adjustments, with the controls in `content` under a disclosure
/// arrow. Ticking the box opens it; the arrow opens it without ticking. While the box is
/// unticked the controls are greyed out and nothing is applied on the GPU; their values are kept
/// for when it is ticked again.
struct GPUAdjustments<Content: View>: View {
    @Bindable var model: DisplayModel
    @ViewBuilder var content: () -> Content
    @AppStorage("showsGPUAdjustments") private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.top, 8)
            .disabled(!model.gpuEnabled)
        } label: {
            Toggle("Adjust colors using GPU", isOn: $model.gpuEnabled)
                .toggleStyle(.checkbox)
                .help("Unticked: the picture is changed only through the monitor's own settings")
        }
        .onChange(of: model.gpuEnabled) { _, enabled in
            if enabled { isExpanded = true }
        }
    }
}

/// "Restore Previous Values" (the state read at launch) and "Reset Values to Factory Defaults",
/// with an inline confirmation because a dialog would close the menu bar popover.
struct RestoreButtons: View {
    let model: DisplayModel
    @State private var confirmsReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.restorePreviousValues()
            } label: {
                Label("Restore Previous Values", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.isBusy || !model.differsFromLaunch)
            .help("Put everything back as it was before Menubar DDC Control started")

            if model.link == .hardware {
                if confirmsReset {
                    HStack(spacing: 8) {
                        Text("Reset every monitor setting?")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button("Cancel") { confirmsReset = false }
                        Button("Reset", role: .destructive) {
                            confirmsReset = false
                            model.resetToFactoryDefaults()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button {
                        confirmsReset = true
                    } label: {
                        Label("Reset Values to Factory Defaults", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isBusy)
                }
            }
            if model.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Working… every value is read back when it finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LinkBadge: View {
    let link: DisplayModel.Link

    var body: some View {
        switch link {
        case .probing:
            ProgressView().controlSize(.small)
        case .hardware:
            Label("DDC/CI", systemImage: "cable.connector")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Settings are sent to the monitor itself")
        case .softwareOnly:
            Label("Software", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("This connection does not carry DDC/CI; adjustments are made by the GPU")
        }
    }
}

/// Resizes the hosting window to its content, keeping the top edge in place. The menu bar
/// window sizes itself once when opened and does not grow when content expands, which pushed
/// the Settings/Quit row out of view when a disclosure was expanded.
struct FitWindowToContent: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, height > 0 else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - height) > 0.5 else { return }
            let resized = NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height)
            window.setFrame(window.frameRect(forContentRect: resized), display: true, animate: false)
        }
    }
}

struct NoticeLabel: View {
    let notice: Notice

    var body: some View {
        Label(notice.text, systemImage: notice.isProblem ? "exclamationmark.triangle" : "info.circle")
            .foregroundStyle(notice.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

import SwiftUI
import XeneonKit

/// A labelled slider with its value on the title row, clear of the track.
struct ValueSlider: View {
    let title: String
    var systemImage: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Values snap to multiples of this. Applied in the binding rather than as the slider's
    /// `step`, which on macOS draws a tick mark per step.
    var step: Double = 1
    var tint: Color?
    var format: (Double) -> String = { String(Int($0.rounded())) }

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
        }
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
    }
}

/// Colour temperature in kelvin, driven by VCP 0x0C in steps of VCP 0x0B.
struct TemperatureSlider: View {
    let model: DisplayModel

    var body: some View {
        let increment = max(model.value(.colorTemperatureIncrement), 1)
        ValueSlider(title: "White point", systemImage: "thermometer.medium", value: model.binding(.colorTemperatureRequest),
                    range: 0...Double(model.maximum(.colorTemperatureRequest)),
                    format: { "\(ColorTemperature.kelvin(forRequest: Int($0.rounded()), increment: increment)) K" })
    }
}

struct PresetPicker: View {
    let model: DisplayModel

    var body: some View {
        let presets = model.capabilities?.vcp[.colorPreset] ?? []
        Picker("Colour preset", selection: Binding(
            get: { UInt8(clamping: model.value(.colorPreset)) },
            set: { model.set(.colorPreset, Int($0)) }
        )) {
            ForEach(presets, id: \.self) { Text(VCPNames.colorPreset($0)).tag($0) }
            if !presets.contains(UInt8(clamping: model.value(.colorPreset))) {
                Text(VCPNames.colorPreset(UInt8(clamping: model.value(.colorPreset)))).tag(UInt8(clamping: model.value(.colorPreset)))
            }
        }
    }
}

struct GainSliders: View {
    let model: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VCPSlider(model: model, code: .redGain, title: "Red", tint: .red)
            VCPSlider(model: model, code: .greenGain, title: "Green", tint: .green)
            VCPSlider(model: model, code: .blueGain, title: "Blue", tint: .blue)
            if !model.isUserPresetActive {
                Text("Changing a gain switches to the \(VCPNames.colorPreset(model.userPreset ?? 0x0B)) preset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SoftwareSliders: View {
    @Bindable var model: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ValueSlider(title: "Brightness", systemImage: "sun.min", value: $model.software.brightness,
                        range: SoftwareAdjustment.brightnessRange, step: 0.01, format: Self.percent)
            ValueSlider(title: "Red", value: $model.software.red, range: SoftwareAdjustment.gainRange, step: 0.01,
                        tint: .red, format: Self.percent)
            ValueSlider(title: "Green", value: $model.software.green, range: SoftwareAdjustment.gainRange, step: 0.01,
                        tint: .green, format: Self.percent)
            ValueSlider(title: "Blue", value: $model.software.blue, range: SoftwareAdjustment.gainRange, step: 0.01,
                        tint: .blue, format: Self.percent)
            ValueSlider(title: "Gamma", value: $model.software.gamma, range: SoftwareAdjustment.gammaRange, step: 0.01,
                        format: { String(format: "%.2f", $0) })
            Button("Reset Software Adjustment") { model.software = .identity }
                .disabled(model.software.isIdentity)
        }
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
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

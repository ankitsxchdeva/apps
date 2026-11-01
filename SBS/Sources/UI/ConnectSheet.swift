import CoreBluetooth
import SwiftUI
import DesignSystem

/// Pick the scale that sits in `slot`. Scans while open.
struct ConnectSheet: View {
    let slot: Slot

    @Environment(ScaleManager.self) private var scales
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpace.l) {
                DSHeader("Scale \(slot.name)", subtitle: "Turn the scale on and keep it close.")
                TextField("What's on it? e.g. V60", text: $label)
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsInk)
                    .submitLabel(.done)
                    .padding(DSSpace.m)
                    .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
                    .accessibilityLabel("Label for scale \(slot.name)")
                if scales.bluetoothState == .unauthorized {
                    EmptyStateView(
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        title: "Bluetooth is off for SBS",
                        message: "Allow Bluetooth in Settings to connect a scale."
                    )
                    .frame(maxWidth: .infinity)
                } else if scales.bluetoothState == .poweredOff {
                    EmptyStateView(
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        title: "Bluetooth is off",
                        message: "Turn on Bluetooth in Control Center to connect a scale."
                    )
                    .frame(maxWidth: .infinity)
                } else if scales.nearby.isEmpty {
                    VStack(spacing: DSSpace.m) {
                        ProgressView()
                        Text("Looking for scales")
                            .font(.dsBody)
                            .foregroundStyle(Color.dsInkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DSSpace.xl)
                } else {
                    VStack(spacing: DSSpace.s) {
                        ForEach(scales.nearby) { scale in
                            Button {
                                scales.assign(scale.id, to: slot)
                                Haptics.firm()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: DSSpace.xs) {
                                        Text(scale.name)
                                            .font(.dsHeadline)
                                            .foregroundStyle(Color.dsInk)
                                        Text(scale.isBeta ? "\(scale.brand) · Beta" : scale.brand)
                                            .font(.dsCaption)
                                            .foregroundStyle(Color.dsInkSecondary)
                                    }
                                    Spacer()
                                    Text("Use as \(slot.name)")
                                        .font(.dsCaption)
                                        .foregroundStyle(.tint)
                                }
                                .padding(DSSpace.m)
                                .frame(minHeight: 52)
                                .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if scales.slots[slot]?.status != .empty {
                    Button("Forget scale \(slot.name)") {
                        scales.forget(slot)
                        Haptics.firm()
                        dismiss()
                    }
                    .buttonStyle(PillButtonStyle(.quiet))
                }
            }
            .padding(DSSpace.l)
            .dsScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            label = scales.labels[slot] ?? ""
            scales.startScan()
        }
        .onDisappear {
            scales.setLabel(label, for: slot)
            scales.stopScan()
        }
    }
}

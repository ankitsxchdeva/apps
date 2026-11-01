import SwiftUI
import DesignSystem

/// Home = the test bench. Two to four scales, one clock, one button. Past runs sit
/// underneath for when you want them.
struct ContentView: View {
    @Environment(ScaleManager.self) private var scales
    @Environment(RunStore.self) private var store
    @Environment(Recorder.self) private var recorder

    @State private var connecting: Slot?
    @State private var finished: Run?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpace.l) {
                    clock
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DSSpace.m), GridItem(.flexible())], spacing: DSSpace.m) {
                        ForEach(Slot.allCases) { slot in
                            ScaleCard(slot: slot, state: scales.slots[slot] ?? .init(), time: time(slot)) {
                                Haptics.tap()
                                connecting = slot
                            }
                            // No swapping scales mid-run, but keep the live weights at full strength.
                            .allowsHitTesting(recorder.phase == .idle)
                        }
                    }
                    if recorder.phase == .recording {
                        PourChart(run: recorder.run)
                            .frame(height: 220)
                            .padding(DSSpace.m)
                            .dsCard()
                    }
                    action
                    if !store.runs.isEmpty {
                        history
                    }
                }
                .padding(DSSpace.l)
            }
            .dsScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Run.ID.self) { id in
                if let run = store.runs.first(where: { $0.id == id }) {
                    RunDetailView(run: run)
                }
            }
        }
        .sheet(item: $connecting) { slot in
            ConnectSheet(slot: slot)
        }
        .sheet(item: $finished) { run in
            NavigationStack {
                RunDetailView(run: run) { keep, run in
                    if keep { store.save(run) }
                }
            }
        }
        .onAppear(perform: screenshotHooks)
    }

    // MARK: - Pieces

    /// The anchor number: the time of whichever scale started first.
    private var clock: some View {
        Text(elapsed.clockText)
            .font(.dsDisplay)
            .monospacedDigit()
            .foregroundStyle(recorder.phase == .idle ? Color.dsInkSecondary : Color.dsInk)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText())
            .accessibilityLabel("Elapsed time")
    }

    private var elapsed: TimeInterval {
        guard recorder.phase == .recording else { return 0 }
        return Slot.allCases.compactMap(time).max() ?? 0
    }

    /// The scale's own timer, or for scales without one, the latest recorded time.
    private func time(_ slot: Slot) -> TimeInterval? {
        if let timer = scales.slots[slot]?.latest?.timer { return timer }
        return recorder.phase == .recording ? recorder.run.samples(slot).last?.t : nil
    }

    @ViewBuilder
    private var action: some View {
        switch recorder.phase {
        case .idle:
            Button("Tare and reset all") {
                Haptics.firm()
                recorder.start()
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!scales.canStart)
            .opacity(scales.canStart ? 1 : 0.4)
        case .waiting:
            Button("Cancel") {
                Haptics.tap()
                _ = recorder.stop()
            }
            .buttonStyle(PillButtonStyle(.quiet))
        case .recording:
            Button("Stop") {
                Haptics.success()
                finished = recorder.stop()
            }
            .buttonStyle(PillButtonStyle(.destructive))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            Text("Runs")
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
            ForEach(store.runs) { run in
                NavigationLink(value: run.id) {
                    HStack(spacing: DSSpace.m) {
                        Text(run.title)
                            .font(.dsBody)
                            .foregroundStyle(Color.dsInk)
                            .lineLimit(1)
                        Spacer(minLength: DSSpace.s)
                        Text(Duration.seconds(run.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.dsCaption)
                            .monospacedDigit()
                            .foregroundStyle(Color.dsInkSecondary)
                    }
                    .padding(DSSpace.m)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.delete(run)
                        Haptics.firm()
                    }
                }
            }
        }
    }

    // MARK: - Debug

    private func screenshotHooks() {
        #if DEBUG
        // Screenshot hooks for UI verification without touch automation.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-sbs-screenshot-run") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { recorder.start() }
        }
        if args.contains("-sbs-screenshot-summary") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { recorder.start() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { finished = recorder.stop() }
        }
        #endif
    }
}

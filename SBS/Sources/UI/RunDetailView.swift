import SwiftUI
import DesignSystem

/// A finished run: both curves and the numbers that differ. Shown right after
/// a run (with Save / Discard) and again from history.
struct RunDetailView: View {
    @State var run: Run
    /// Set for a run that hasn't been saved yet.
    var onDecide: ((_ keep: Bool, _ run: Run) -> Void)?

    @Environment(RunStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?

    private var isNew: Bool { onDecide != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.l) {
                DSHeader(isNew ? "Run done" : run.title, subtitle: run.date.formatted(date: .abbreviated, time: .shortened))
                TextField("What did you test?", text: $run.note)
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsInk)
                    .submitLabel(.done)
                    .padding(DSSpace.m)
                    .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
                if let score = run.matchScore {
                    match(score)
                }
                stats
                chart(.weight)
                chart(.flow)
                if isNew {
                    Button("Save run") { decide(keep: true) }
                        .buttonStyle(PillButtonStyle())
                    Button("Discard") { decide(keep: false) }
                        .buttonStyle(PillButtonStyle(.quiet))
                } else if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PillButtonStyle(.quiet))
                }
            }
            .padding(DSSpace.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .dsScreen()
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isNew)
        .task { if !isNew { exportURL = writeCSV() } }
        .onDisappear {
            if !isNew { store.save(run) }
        }
    }

    // MARK: - Numbers

    /// The anchor: how closely the two pours tracked each other.
    private func match(_ score: Int) -> some View {
        VStack(spacing: DSSpace.xs) {
            Text("\(score)")
                .font(.dsDisplay)
                .monospacedDigit()
                .foregroundStyle(Color.dsInk)
            HStack(spacing: DSSpace.s) {
                Circle().fill(Slot.a.color).frame(width: 8, height: 8)
                Circle().fill(Slot.b.color).frame(width: 8, height: 8)
                Text("match · \(verdict(score))")
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpace.m)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Match \(score) out of 100, \(verdict(score))")
    }

    private func verdict(_ score: Int) -> String {
        switch score {
        case 90...: "nearly identical pours"
        case 75..<90: "close"
        case 50..<75: "noticeably different"
        default: "very different"
        }
    }

    private var stats: some View {
        let a = PourStats(run.a)
        let b = PourStats(run.b)
        return VStack(spacing: 0) {
            statRow("", a: "A", b: "B", diff: "B − A", header: true)
            statRow("Final", a: grams(a?.finalGrams), b: grams(b?.finalGrams),
                    diff: grams(delta(a?.finalGrams, b?.finalGrams), signed: true))
            statRow("Pour time", a: seconds(a?.pourTime), b: seconds(b?.pourTime),
                    diff: seconds(delta(a?.pourTime, b?.pourTime), signed: true))
            statRow("Avg flow", a: flow(a?.averageFlow), b: flow(b?.averageFlow),
                    diff: flow(delta(a?.averageFlow, b?.averageFlow), signed: true))
            statRow("Peak flow", a: flow(a?.peakFlow), b: flow(b?.peakFlow),
                    diff: flow(delta(a?.peakFlow, b?.peakFlow), signed: true))
        }
        .padding(DSSpace.m)
        .dsCard()
    }

    private func statRow(_ label: String, a: String, b: String, diff: String, header: Bool = false) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.dsInkSecondary)
            Text(a).frame(maxWidth: .infinity, alignment: .trailing)
            Text(b).frame(maxWidth: .infinity, alignment: .trailing)
            Text(diff)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(header ? Color.dsInkSecondary : Color.dsInk)
        }
        .font(header ? .dsCaption : .dsBody)
        .monospacedDigit()
        .foregroundStyle(header ? Color.dsInkSecondary : Color.dsInk)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, DSSpace.s)
    }

    private func delta(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return b - a
    }

    private func format(_ value: Double?, _ unit: String, signed: Bool) -> String {
        guard let value else { return "–" }
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        return (signed ? value.formatted(style.sign(strategy: .always(includingZero: false))) : value.formatted(style)) + " " + unit
    }

    private func grams(_ v: Double?, signed: Bool = false) -> String { format(v, "g", signed: signed) }
    private func seconds(_ v: Double?, signed: Bool = false) -> String { format(v, "s", signed: signed) }
    private func flow(_ v: Double?, signed: Bool = false) -> String { format(v, "g/s", signed: signed) }

    private func chart(_ metric: PourChart.Metric) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            Text(metric.title)
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
            PourChart(run: run, metric: metric)
                .frame(height: 200)
        }
        .padding(DSSpace.m)
        .dsCard()
    }

    // MARK: - Actions

    private func decide(keep: Bool) {
        Haptics.firm()
        onDecide?(keep, run)
        dismiss()
    }

    private func writeCSV() -> URL? {
        let name = "SBS " + run.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let url = URL.temporaryDirectory.appending(path: "\(name).csv")
        do {
            try run.csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

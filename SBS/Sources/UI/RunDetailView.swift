import SwiftUI
import DesignSystem

/// A finished run: every curve and the numbers that differ. Shown right after
/// a run (with Save / Discard) and again from history.
struct RunDetailView: View {
    @State var run: Run
    /// Set for a run that hasn't been saved yet.
    var onDecide: ((_ keep: Bool, _ run: Run) -> Void)?

    @Environment(RunStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
                if scores.count == 1, let only = scores.first {
                    match(only.match, slot: only.slot)
                } else if !scores.isEmpty {
                    matches
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

    /// Each scale after A, with how closely it tracked A.
    private var scores: [(slot: Slot, match: Run.Match)] {
        run.slots.filter { $0 != .a }.compactMap { slot in
            run.match(slot).map { (slot, $0) }
        }
    }

    /// The anchor: how closely the two pours tracked each other.
    private func match(_ match: Run.Match, slot: Slot) -> some View {
        let score = match.score
        return VStack(spacing: DSSpace.xs) {
            Text("\(score)")
                .font(.dsDisplay)
                .monospacedDigit()
                .foregroundStyle(Color.dsInk)
            HStack(spacing: DSSpace.s) {
                Circle().fill(Slot.a.color).frame(width: 8, height: 8)
                Circle().fill(slot.color).frame(width: 8, height: 8)
                Text("match · \(verdict(score))")
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
            }
            Text(parts(match))
                .font(.dsCaption)
                .monospacedDigit()
                .foregroundStyle(Color.dsInkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpace.m)
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Match \(score) out of 100, \(verdict(score)). \(parts(match))")
    }

    /// Three or four scales: one row per scale, each scored against A.
    private var matches: some View {
        VStack(spacing: 0) {
            ForEach(scores, id: \.slot) { slot, match in
                let score = match.score
                // Stacks at accessibility text sizes so the verdict fits.
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpace.xs))
                    : AnyLayout(HStackLayout(spacing: DSSpace.s))
                layout {
                    VStack(alignment: .leading, spacing: DSSpace.xs) {
                        HStack(spacing: DSSpace.s) {
                            Circle().fill(slot.color).frame(width: 8, height: 8)
                            Text("\(run.seriesName(slot)) vs A")
                                .font(.dsBody)
                                .foregroundStyle(Color.dsInk)
                        }
                        Text("\(verdict(score)) · \(parts(match))")
                            .font(.dsCaption)
                            .monospacedDigit()
                            .foregroundStyle(Color.dsInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: DSSpace.s)
                    }
                    Text("\(score)")
                        .font(.dsTitle)
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DSSpace.s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(run.seriesName(slot)) matched A \(score) out of 100, \(verdict(score)). \(parts(match))")
            }
        }
        .padding(DSSpace.m)
        .dsCard()
    }

    private func verdict(_ score: Int) -> String {
        switch score {
        case 99...: "machine-level"
        case 95..<99: "nearly identical"
        case 85..<95: "close"
        case 70..<85: "noticeably different"
        default: "very different"
        }
    }

    /// What the score is made of.
    private func parts(_ match: Run.Match) -> String {
        "curve \(match.curve) · flow \(match.flow)"
    }

    /// One column per scale. A two-scale run also gets a difference column.
    /// At accessibility text sizes each column becomes its own block.
    private var stats: some View {
        let slots = run.slots
        let all = slots.map { PourStats(run.samples($0)) }
        let pair = slots.count == 2
        let metrics: [(label: String, value: (PourStats?) -> Double?, format: (Double?, Bool) -> String)] = [
            ("Final", { $0?.finalGrams }, grams),
            ("Pour time", { $0?.pourTime }, seconds),
            ("Avg flow", { $0?.averageFlow }, flow),
            ("Peak flow", { $0?.peakFlow }, flow),
        ]
        // Each column: a title and one formatted value per metric.
        var columns = slots.indices.map { i in
            (title: slots[i].name, values: metrics.map { $0.format($0.value(all[i]), false) })
        }
        if pair {
            columns.append((title: "\(slots[1].name) − \(slots[0].name)", values: metrics.map {
                $0.format(delta($0.value(all[0]), $0.value(all[1])), true)
            }))
        }
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DSSpace.m) {
                    ForEach(columns, id: \.title) { column in
                        VStack(alignment: .leading, spacing: DSSpace.xs) {
                            Text(column.title)
                                .font(.dsHeadline)
                                .foregroundStyle(Color.dsInk)
                            ForEach(metrics.indices, id: \.self) { m in
                                Text("\(metrics[m].label): \(column.values[m])")
                                    .font(.dsBody)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.dsInk)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    statRow("", columns.map(\.title), header: true)
                    ForEach(metrics.indices, id: \.self) { m in
                        statRow(metrics[m].label, columns.map { $0.values[m] })
                    }
                }
            }
        }
        .padding(DSSpace.m)
        .dsCard()
    }

    private func statRow(_ label: String, _ values: [String], header: Bool = false) -> some View {
        HStack {
            // Caption-sized so every label fits whole, not shrunk unevenly.
            Text(label)
                .font(.dsCaption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.dsInkSecondary)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value).frame(maxWidth: .infinity, alignment: .trailing)
            }
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

    private func grams(_ v: Double?, signed: Bool) -> String { format(v, "g", signed: signed) }
    private func seconds(_ v: Double?, signed: Bool) -> String { format(v, "s", signed: signed) }
    private func flow(_ v: Double?, signed: Bool) -> String { format(v, "g/s", signed: signed) }

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

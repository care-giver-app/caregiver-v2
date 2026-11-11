import SwiftUI

/// Quick log (PRD "The tab bar", "Quick log"; Figma section 5 · Quick log 448:4146): one
/// sheet that runs in three parts — what to record, when it happened, then a step for
/// each thing picked — and ends on a result reporting item by item. It draws
/// `QuickLogModel.part`; everything it decides is the model's.
///
/// Back steps back a part with what was entered still there; Cancel, where there is no
/// part to step back to, goes back to whatever raised it with nothing saved. Done on the
/// result goes back too. However the sheet goes, `onEnd` hears how the run ended, so the
/// screens beneath read themselves again when it saved something. Add a tracker hands
/// over to `onAddTracker`, which puts Add tracker in Quick log's place.
struct QuickLogV1Sheet: View {
    let onAddTracker: () -> Void
    let onEnd: (QuickLogModel.Outcome?) -> Void

    @State private var model: QuickLogModel
    @Environment(\.dismiss) private var dismiss

    init(start: QuickLogStart, receiver: TeamReceiver, home: HomeService, trackers: TrackersService,
         onAddTracker: @escaping () -> Void, onEnd: @escaping (QuickLogModel.Outcome?) -> Void) {
        self.init(model: QuickLogModel(start: start, receiver: receiver, home: home, trackers: trackers),
                  onAddTracker: onAddTracker, onEnd: onEnd)
    }

    init(model: QuickLogModel, onAddTracker: @escaping () -> Void = {},
         onEnd: @escaping (QuickLogModel.Outcome?) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onAddTracker = onAddTracker
        self.onEnd = onEnd
    }

    private var zone: TimeZone { model.receiver.timeZone }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.Colors.surface)
                .navigationTitle("Quick log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(model.part == .submitting)
        .task { if model.part == .loading { await model.load() } }
        .onChange(of: model.wantsAddTracker) { _, wants in if wants { onAddTracker() } }
        .onDisappear { onEnd(model.outcome) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.part == .result {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        } else if model.canGoBack {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.back() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .disabled(model.isLoadingFields)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(model.part == .submitting)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.part {
        case .loading:
            StrideLoadingView()
        case .loadFailed:
            StrideErrorState(message: QuickLogText.loadFailed) { Task { await model.load() } }
        case .pick:
            pick
        case .when:
            whenPart
        case .step(let i):
            step(i, submitting: false)
        case .submitting:
            step(model.selection.count - 1, submitting: true)
        case .result:
            result
        }
    }

    // MARK: - What to record (Figma 448:4147, 448:4603, 448:4639)

    private var pick: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuickLogHeading(text: QuickLogText.pickHeading)
                .padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let now = Date()
                    let occurrences = model.pickerOccurrences
                    if !occurrences.isEmpty {
                        QuickLogSectionLabel(text: QuickLogText.waitingLabel)
                        ForEach(occurrences) { o in
                            pickButton(.occurrence(entryID: o.entry.id)) {
                                QuickLogRow(title: o.tracker.name,
                                            subtitle: QuickLogText.occurrenceLine(o.entry, now: now, zone: zone),
                                            selected: model.isPicked(.occurrence(entryID: o.entry.id))) {
                                    QuickLogTile.tracker(icon: o.tracker.icon, color: o.tracker.color)
                                } trailing: {
                                    if o.entry.state == .unrecorded { HomeStateBadge(state: .unrecorded) }
                                }
                            }
                        }
                        Color.clear.frame(height: 8)
                    }
                    if !model.pickerTrackers.isEmpty {
                        QuickLogSectionLabel(text: QuickLogText.trackersLabel)
                        ForEach(model.pickerTrackers) { t in
                            pickButton(.tracker(id: t.id)) {
                                QuickLogRow(title: t.name, selected: model.isPicked(.tracker(id: t.id))) {
                                    QuickLogTile.tracker(icon: t.icon, color: t.color)
                                }
                            }
                        }
                    }
                    if model.offersJournalNote {
                        pickButton(.journalNote) {
                            QuickLogRow(title: QuickLogText.journalNote, selected: model.isPicked(.journalNote)) {
                                QuickLogTile.journalNote()
                            }
                        }
                    }
                    if model.offersAddTracker {
                        Button { model.chooseAddTracker() } label: {
                            AddTrackerActionRow(title: QuickLogText.addTracker)
                        }
                        .buttonStyle(.plain)
                    }
                    if let line = model.noTrackersLine {
                        QuickLogCaption(text: line)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            QuickLogPrimaryButton(title: "Next", enabled: model.canContinueFromPick) {
                model.continueFromPick()
            }
        }
    }

    private func pickButton<Label: View>(_ item: QuickLogModel.Item, @ViewBuilder label: () -> Label) -> some View {
        Button { model.toggle(item) } label: { label() }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.isPicked(item) ? .isSelected : [])
    }

    // MARK: - When (Figma 448:4254, 448:4290)

    private var whenPart: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuickLogHeading(text: QuickLogText.whenHeading)
                .padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let now = Date()
                    whenRow(.now, title: QuickLogText.now) {
                        Text(HomeText.clock(now, zone: zone))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    whenRow(.earlierToday, title: QuickLogText.earlierToday) {
                        if model.when != .earlierToday {
                            Text(QuickLogText.pickATime).foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    if model.when == .earlierToday {
                        HStack(spacing: 12) {
                            timeBox(label: "Time", selection: $model.earlierTime,
                                    range: model.today.start(in: zone)...now, components: .hourAndMinute)
                        }
                    }
                    if model.offersFuture {
                        whenRow(.future, title: QuickLogText.futureTime) {
                            if model.when != .future {
                                Text(QuickLogText.planIt).foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    if model.when == .future {
                        HStack(alignment: .top, spacing: 12) {
                            timeBox(label: "Date", selection: $model.futureTime,
                                    range: model.today.start(in: zone)...Date.distantFuture, components: .date)
                            timeBox(label: "Time", selection: $model.futureTime,
                                    range: model.today.start(in: zone)...Date.distantFuture, components: .hourAndMinute)
                        }
                        Toggle(QuickLogText.alertIfUnrecorded, isOn: $model.alertIfUnrecorded)
                            .toggleStyle(.stride)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 14)
                            .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
                            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
                            .padding(.top, Theme.Spacing.xs)
                    }
                    QuickLogCaption(text: model.isPlanning ? QuickLogText.planningCaption : QuickLogText.oneTime)
                        .padding(.top, Theme.Spacing.xs)
                    QuickLogProblems(problems: model.whenProblems)
                    if model.fieldsFailed != nil {
                        StrideAlertBanner(message: QuickLogText.fieldsFailed)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            QuickLogPrimaryButton(title: "Next", enabled: model.whenProblems.isEmpty && !model.selection.isEmpty,
                                  isLoading: model.isLoadingFields) {
                Task { await model.continueFromWhen() }
            }
        }
    }

    private func whenRow<Value: View>(_ when: QuickLogModel.When, title: String,
                                      @ViewBuilder value: () -> Value) -> some View {
        let selected = model.when == when
        return Button { model.when = when } label: {
            HStack(spacing: 12) {
                QuickLogRadio(selected: selected)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                value()
                    .font(.system(size: 14, weight: .medium))
            }
            .quickLogCard(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func timeBox(label: String, selection: Binding<Date>, range: ClosedRange<Date>,
                         components: DatePicker.Components) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QuickLogFieldLabel(text: label)
            DatePicker(label, selection: selection, in: range, displayedComponents: components)
            .labelsHidden()
            .environment(\.timeZone, zone)
            .quickLogInputBox()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Steps (Figma 448:4344, 448:4390, 448:4425, 448:4464, 448:4493)

    @ViewBuilder
    private func step(_ index: Int, submitting: Bool) -> some View {
        let selection = model.selection
        if selection.indices.contains(index), let step = model.step(for: selection[index]) {
            let item = selection[index]
            let problems = model.problems(for: item)
            VStack(alignment: .leading, spacing: 0) {
                QuickLogSectionLabel(text: QuickLogText.stepLabel(index, of: selection.count,
                                                                  planning: model.isPlanning))
                    .padding(.bottom, 10)
                stepHeader(step)
                    .padding(.bottom, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        stepBody(step, item: item)
                        QuickLogProblems(problems: problems)
                    }
                    .padding(.bottom, Theme.Spacing.md)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .disabled(submitting)
                QuickLogPrimaryButton(title: submitting || model.isLastStep ? "Save" : "Next",
                                      enabled: problems.isEmpty, isLoading: submitting) {
                    Task { await model.advance() }
                }
            }
            // A fresh scroll position and focus for each step.
            .id(item)
        }
    }

    private func stepHeader(_ step: QuickLogModel.Step) -> some View {
        let now = Date()
        let runTime = HomeText.entryWhen(model.runTime(now: now), now: now, zone: zone)
        return HStack(spacing: 12) {
            switch step {
            case .occurrence(let o, _):
                QuickLogTile.tracker(icon: o.tracker.icon, color: o.tracker.color, size: 44)
                stepTitle(o.tracker.name, QuickLogText.occurrenceLine(o.entry, now: now, zone: zone))
            case .tracker(let t, _):
                QuickLogTile.tracker(icon: t.icon, color: t.color, size: 44)
                stepTitle(t.name, runTime)
            case .journalNote:
                QuickLogTile.journalNote(size: 44)
                stepTitle(QuickLogText.journalNote, runTime)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func stepBody(_ step: QuickLogModel.Step, item: QuickLogModel.Item) -> some View {
        let draft = draftBinding(item)
        switch step {
        case .occurrence(_, let fields):
            HStack(spacing: Theme.Spacing.sm) {
                StrideChip(label: "Log it", isSelected: draft.wrappedValue.choice == .logIt) {
                    draft.wrappedValue.choice = .logIt
                }
                StrideChip(label: "Skip", isSelected: draft.wrappedValue.choice == .skip) {
                    draft.wrappedValue.choice = .skip
                }
            }
            if draft.wrappedValue.choice == .logIt {
                EntryFieldInputs(fields: fields, values: draft.values, zone: zone)
            }
            QuickLogNoteInput(text: draft.note)
        case .tracker(_, let fields):
            EntryFieldInputs(fields: fields, values: draft.values, zone: zone)
            if model.isPlanning {
                QuickLogCaption(text: QuickLogText.plannedStepCaption)
            } else {
                QuickLogNoteInput(text: draft.note)
            }
        case .journalNote:
            QuickLogNoteInput(text: draft.note, minHeight: 200)
        }
    }

    private func draftBinding(_ item: QuickLogModel.Item) -> Binding<QuickLogModel.Draft> {
        Binding(get: { model.draft(for: item) },
                set: { new in model.updateDraft(item) { $0 = new } })
    }

    // MARK: - Result (Figma 448:4530, 448:4571)

    private var result: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuickLogSectionLabel(text: QuickLogText.resultsLabel)
                .padding(.bottom, Theme.Spacing.xs)
            QuickLogHeading(text: QuickLogText.resultsHeading(saved: model.results.filter(\.saved).count,
                                                              of: model.results.count,
                                                              planning: model.isPlanning))
                .padding(.bottom, 18)
            ScrollView {
                VStack(spacing: 8) {
                    let now = Date()
                    ForEach(model.results) { r in
                        resultRow(r, now: now)
                    }
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func resultRow(_ r: QuickLogModel.Result, now: Date) -> some View {
        let line = QuickLogText.resultLine(r, planning: model.isPlanning, now: now, zone: zone)
        var reason: String?
        if case .failed(let message) = r.status { reason = message }
        return QuickLogRow(title: r.title, subtitle: line, subtitleColor: r.saved ? nil : Theme.Colors.alert,
                           detail: reason, selected: nil) {
            if let t = r.tracker {
                QuickLogTile.tracker(icon: t.icon, color: t.color)
            } else {
                QuickLogTile.journalNote()
            }
        } trailing: {
            if r.saved {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.success)
                    .accessibilityLabel(QuickLogText.saved)
            } else if r.retryable {
                if model.retrying.contains(r.item) {
                    ProgressView().tint(Theme.Colors.accent)
                } else {
                    Button("Retry") { Task { await model.retry(r.item) } }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Pieces

/// "What to record", "When did it happen?", "2 of 3 saved".
private struct QuickLogHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "WAITING", "STEP 1 OF 3", "RESULTS".
private struct QuickLogSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.72)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

private struct QuickLogCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What stops the part going on, in the alert color.
struct QuickLogProblems: View {
    let problems: [String]

    var body: some View {
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(problems, id: \.self) { Text($0) }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.alert)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Next or Save, pinned under the part's scroll (Figma 448:4252).
private struct QuickLogPrimaryButton: View {
    let title: String
    var enabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        StrideButton(title: title, isLoading: isLoading) {
            guard enabled, !isLoading else { return }
            action()
        }
        .disabled(!enabled || isLoading)
        .opacity(enabled || isLoading ? 1 : 0.5)
        .padding(.top, 12)
    }
}

/// The 34pt (44pt on a step) tile a row leads with: a tracker's icon on its color, or
/// a journal note's page on the violet tint (Figma 448:4165, 448:4233).
private enum QuickLogTile {
    static func tracker(icon: String, color: String, size: CGFloat = 34) -> some View {
        RoundedRectangle(cornerRadius: size >= 44 ? 12 : 10)
            .fill(Color(hex: color))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
    }

    static func journalNote(size: CGFloat = 34) -> some View {
        RoundedRectangle(cornerRadius: size >= 44 ? 12 : 10)
            .fill(Theme.Colors.violetTint)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Theme.Colors.trackerViolet)
            }
            .accessibilityHidden(true)
    }
}

/// A row of the picker or the result (Figma 448:4164, 448:4545): its tile, title and
/// line under it, then whatever trails — a badge and the check on the picker; a check
/// or Retry on the result. `selected` nil draws no check.
private struct QuickLogRow<Tile: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color? = nil
    /// A second, wrapping line: why a result's item did not save.
    var detail: String? = nil
    let selected: Bool?
    @ViewBuilder var tile: Tile
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(subtitleColor ?? Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            trailing
            if let selected {
                QuickLogCheck(selected: selected)
            }
        }
        .contentShape(Rectangle())
        .quickLogCard(selected: selected ?? false)
        .accessibilityElement(children: .combine)
    }
}

extension QuickLogRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, selected: Bool?, @ViewBuilder tile: () -> Tile) {
        self.init(title: title, subtitle: subtitle, selected: selected, tile: tile, trailing: { EmptyView() })
    }
}

/// Figma 448:4174 / 448:4184: a filled check when picked, an empty ring when not.
private struct QuickLogCheck: View {
    let selected: Bool

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(Theme.Colors.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Colors.textOnAccent)
            } else {
                Circle().strokeBorder(Theme.Colors.border, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Figma 448:4270: a filled ring with a dot when chosen.
private struct QuickLogRadio: View {
    let selected: Bool

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(Theme.Colors.accent)
                Circle().fill(Color.white).frame(width: 10, height: 10)
            } else {
                Circle().strokeBorder(Theme.Colors.border, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// The white card a row sits on: a hairline border, or 1.5pt of accent when picked.
    func quickLogCard(selected: Bool) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: selected ? 1.5 : 1)
            }
    }
}

// MARK: - Previews, one per Figma frame

#if DEBUG
/// Drives a model from HomeFixtures (with their write stubs) to the frame's state.
private struct QuickLogPreview: View {
    var start: QuickLogStart = .pick
    var receiver: TeamReceiver = TrackersFixtures.eleanor
    var home: HomeService = HomeFixtures.service()
    var trackers: TrackersService = HomeFixtures.trackersService()
    var drive: @MainActor (QuickLogModel) async -> Void = { _ in }

    @State private var model: QuickLogModel?

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                if let model { QuickLogV1Sheet(model: model) } else { StrideLoadingView() }
            }
            .task {
                let m = QuickLogModel(start: start, receiver: receiver, home: home, trackers: trackers)
                await m.load()
                await drive(m)
                model = m
            }
    }
}

@MainActor
private enum QuickLogPreviewRun {
    static let unrecordedDose = QuickLogModel.Item.occurrence(entryID: HomeFixtures.eveningDoseUnrecorded.id)
    static let bp = QuickLogModel.Item.tracker(id: "bp")
    static let medication = QuickLogModel.Item.tracker(id: "medication")

    static func pickAndGo(_ m: QuickLogModel, _ items: [QuickLogModel.Item], when: QuickLogModel.When = .now) async {
        items.forEach(m.toggle)
        m.continueFromPick()
        m.when = when
        if when == .future { m.alertIfUnrecorded = true }
    }

    static func fillBP(_ m: QuickLogModel) {
        m.updateDraft(bp) {
            $0.values.setNumberText("128", for: "sys")
            $0.values.setNumberText("82", for: "dia")
            $0.note = "Sitting, after dinner"
        }
    }
}

#Preview("1 · What to record (448:4147)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        [R.unrecordedDose, R.bp, .journalNote].forEach(m.toggle)
    }
}

#Preview("2 · When (448:4254)") {
    QuickLogPreview { m in await QuickLogPreviewRun.pickAndGo(m, [QuickLogPreviewRun.bp]) }
}

#Preview("2 · When, planning (448:4290)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.medication, R.bp], when: .future)
    }
}

#Preview("Step, waiting · log it (448:4344)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.unrecordedDose, R.bp, .journalNote])
        await m.continueFromWhen()
        m.updateDraft(R.unrecordedDose) { $0.values.setBool(true, for: "given") }
    }
}

#Preview("Step, waiting · skip (448:4390)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.unrecordedDose, R.bp, .journalNote])
        await m.continueFromWhen()
        m.updateDraft(R.unrecordedDose) { $0.choice = .skip }
    }
}

#Preview("Step, tracker (448:4425)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.unrecordedDose, R.bp, .journalNote])
        await m.continueFromWhen()
        m.updateDraft(R.unrecordedDose) { $0.choice = .skip }
        await m.advance()
        R.fillBP(m)
    }
}

#Preview("Step, journal note (448:4464)") {
    QuickLogPreview(start: .journalNote) { m in
        m.continueFromPick()
        await m.continueFromWhen()
        m.updateDraft(.journalNote) {
            $0.note = "Quiet evening. Watched the game with Marcus and went to bed early."
        }
    }
}

#Preview("Step, planned (448:4493)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.medication, R.bp], when: .future)
        await m.continueFromWhen()
    }
}

#Preview("Results, one failed (448:4530)") {
    var home = HomeFixtures.service()
    home.addJournalNote = { _, _ in throw HomeFixtures.Unreachable() }
    return QuickLogPreview(home: home) { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.unrecordedDose, R.bp, .journalNote])
        await m.continueFromWhen()
        m.updateDraft(R.unrecordedDose) { $0.choice = .skip }
        R.fillBP(m)
        m.updateDraft(.journalNote) { $0.note = "Quiet evening." }
        await m.submit()
    }
}

#Preview("Results, planned (448:4571)") {
    QuickLogPreview { m in
        typealias R = QuickLogPreviewRun
        await R.pickAndGo(m, [R.medication, R.bp], when: .future)
        await m.continueFromWhen()
        await m.submit()
    }
}

#Preview("No active trackers, admin (448:4603)") {
    var home = HomeFixtures.service()
    home.waiting = { _ in [] }
    return QuickLogPreview(home: home, trackers: TrackersFixtures.service(trackers: []))
}

#Preview("No active trackers, caregiver (448:4639)") {
    var home = HomeFixtures.service()
    home.waiting = { _ in [] }
    return QuickLogPreview(receiver: TrackersFixtures.eleanorForCaregiver, home: home,
                           trackers: TrackersFixtures.service(trackers: []))
}

#Preview("From Entry detail, Log it") {
    QuickLogPreview(start: .entry(HomeFixtures.unrecordedDetail, choice: .logIt))
}

#Preview("From Tracker detail, nothing waiting") {
    QuickLogPreview(start: .tracker(id: "weight"))
}

#Preview("Load failed") {
    QuickLogPreview(home: HomeFixtures.service(fail: true))
}
#endif

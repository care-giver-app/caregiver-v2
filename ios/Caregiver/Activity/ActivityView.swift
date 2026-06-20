import SwiftUI
import CaregiverAPI

struct ActivityView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context

    @State private var model = ActivityModel()
    @State private var selectedDate = Date()
    @State private var showDatePicker = false

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        Group {
            if let receiver = context.activeReceiver {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        timelineWidget(receiverID: receiver.receiverId)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)
                }
                .refreshable { await reload() }
            } else {
                EmptyStateView(message: "No receiver selected.")
            }
        }
        .navigationTitle("Activity")
        .earthBackground()
        .navigationDestination(for: EventRef.self) { ref in
            EventDetailView(tracker: ref.tracker, event: ref.event) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }

    // MARK: Reload

    private func reload() async {
        guard let id = context.activeReceiver?.receiverId else { return }
        await model.load(receiverID: id, date: selectedDate, using: session)
    }

    // MARK: Date header

    private var dateHeader: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Spacer()
            Button { showDatePicker = true } label: {
                Text(ActivityDay.label(for: selectedDate))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(isToday)
                .opacity(isToday ? 0.3 : 1)
        }
        .font(.headline)
        .foregroundStyle(Theme.Colors.accent)
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width > 0 { shiftDay(-1) }
                    else if value.translation.width < 0 { shiftDay(1) }
                }
        )
    }

    private func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        // No future days.
        if delta > 0 && next > Date() && !Calendar.current.isDateInToday(next) { return }
        selectedDate = next
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Day", selection: $selectedDate, in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Jump to day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Day content

    /// The timeline as a self-contained glass widget: date-nav header + the day's content.
    @ViewBuilder private func timelineWidget(receiverID: String) -> some View {
        VStack(spacing: 0) {
            dateHeader
            Divider()
            dayContent
        }
        .glassCard()
        .task(id: DayKey(receiverID: receiverID, dayStart: ActivityDay.bounds(for: selectedDate).start)) {
            await reload()
        }
    }

    @ViewBuilder private var dayContent: some View {
        switch model.state {
        case .loading:
            LoadingView()
                .frame(height: 140)
        case .empty:
            EmptyStateView(message: "No activity on \(ActivityDay.label(for: selectedDate)).")
                .frame(height: 140)
        case .error(let message):
            ErrorStateView(message: message) { Task { await reload() } }
                .frame(height: 160)
        case .loaded(let refs):
            VStack(spacing: 0) {
                ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
                    NavigationLink(value: ref) {
                        ActivityRow(ref: ref, isFirst: index == 0, isLast: index == refs.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Reload trigger: re-runs when the active receiver or the selected day changes.
private struct DayKey: Equatable {
    let receiverID: String
    let dayStart: Date
}

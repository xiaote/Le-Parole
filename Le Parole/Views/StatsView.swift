import SwiftUI
import Charts

struct StatsView: View {
    let appActivity: AppActivity
    @State private var vm = StatsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Activity") {
                    DailyActivityChart(dailyCounts: vm.dailyCounts, weekTotal: vm.weekTotal)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                }

                Section("Learning progress") {
                    Picker("Up to", selection: Binding(
                        get: { vm.targetLevel },
                        set: { vm.targetLevel = $0 }
                    )) {
                        Text("None").tag("None")
                        ForEach(Word.cefrLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }

                    if vm.targetLevel != "None" {
                        CumulativeProgressChartView(
                            entries: vm.progressEntries,
                            targetLevel: vm.targetLevel,
                            targetCount: vm.targetWordCount,
                            benchmarks: vm.benchmarks,
                            projection: vm.coverageProjection
                        )
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    } else {
                        Text("Choose a level to see your progress.")
                            .font(.theme(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }

                Section("Overall") {
                    ProgressRow(label: "Mastered",              count: vm.snapshot.mastered,    total: vm.snapshot.total, color: Theme.mastered)
                    ProgressRow(label: "Production (EN → IT)",  count: vm.snapshot.production,  total: vm.snapshot.total, color: Theme.production)
                    ProgressRow(label: "Recognition (IT → EN)", count: vm.snapshot.recognition, total: vm.snapshot.total, color: Theme.recognition)
                    ProgressRow(label: "Not started",           count: vm.snapshot.notStarted,  total: vm.snapshot.total, color: .gray)
                    ProgressRow(label: "Skipped",               count: vm.snapshot.skipped,     total: nil,               color: .secondary)
                }
                
                if !vm.tenseStats.isEmpty {
                    Section("Tense proficiency") {
                        ForEach(vm.tenseStats, id: \.tense) { stat in
                            TenseProgressRow(stat: stat)
                        }
                    }
                }

                Section("By level") {
                    ForEach(Word.cefrLevels, id: \.self) { level in
                        LevelProgressRow(stats: vm.statsFor(level: level))
                    }
                }

                if !vm.snapshot.customCategories.isEmpty {
                    Section("By category") {
                        ForEach(vm.snapshot.customCategories, id: \.self) { category in
                            LevelProgressRow(stats: vm.statsFor(level: category))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Progress")
            .toolbarBackground(Theme.canvas, for: .navigationBar)
        }
        .onAppear {
            if !appActivity.isStudySessionActive {
                vm.setObserving(true)
            }
        }
        .onDisappear {
            vm.setObserving(false)
        }
        .onChange(of: appActivity.isStudySessionActive) { _, isStudying in
            vm.setObserving(!isStudying)
        }
    }
}

// MARK: - Daily Activity Chart

private struct DailyActivityChart: View {
    let dailyCounts: [DailyCount]
    let weekTotal: Int

    @State private var selectedDate: Date?

    private var yMax: Double {
        let maxTotal = dailyCounts.map(\.total).max() ?? 0
        return Double(max(2, maxTotal + 2))
    }

    private var selectedCount: DailyCount? {
        guard let sel = selectedDate else { return nil }
        return dailyCounts.first { $0.date == sel }
    }

    // Placeholder keeps the ZStack height stable when nothing is selected.
    private var placeholderCount: DailyCount {
        DailyCount(dateString: AppDateFormatter.string(from: Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Both headers are always in the layout (same height), crossfaded via opacity.
            // Animating only on nil↔non-nil prevents jank while dragging bar-to-bar.
            ZStack(alignment: .leading) {
                weekSummaryHeader
                    .opacity(selectedCount == nil ? 1 : 0)
                selectedDayHeader(selectedCount ?? placeholderCount)
                    .opacity(selectedCount == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.15), value: selectedCount == nil)

            // Review-answer volume. This deliberately does not infer learning
            // progress from a card's stage after an answer.
            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(dailyCounts) { entry in
                        BarMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("Answers", entry.reviewAttempts)
                        )
                        .foregroundStyle(Theme.primary)
                        .opacity(
                            selectedDate == nil ||
                            Calendar.current.startOfDay(for: entry.date) == selectedDate
                                ? 1.0 : 0.35
                        )
                        .cornerRadius(3, style: .continuous)
                    }

                    if let sel = selectedDate {
                        RuleMark(x: .value("Selected", sel, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: 0...yMax)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        if let date = value.as(Date.self) {
                            let isFirst = Calendar.current.component(.day, from: date) == 1
                            AxisValueLabel {
                                VStack(spacing: 1) {
                                    if isFirst {
                                        Text(date, format: .dateTime.month(.abbreviated))
                                            .font(.theme(.caption2))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("").font(.theme(.caption2))
                                    }
                                    Text(date, format: .dateTime.weekday(.narrow))
                                        .font(.theme(.caption2, weight: Calendar.current.isDateInToday(date) ? .bold : .regular))
                                        .foregroundStyle(
                                            Calendar.current.isDateInToday(date)
                                                ? Theme.primary : Color.secondary
                                        )
                                }
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let plotArea = geometry[plotFrame]
                                        let xPosition = value.location.x - plotArea.origin.x
                                        if let tapped: Date = proxy.value(atX: xPosition) {
                                            let day = Calendar.current.startOfDay(for: tapped)
                                            if selectedDate != day { selectedDate = day }
                                        }
                                    }
                                    .onEnded { _ in selectedDate = nil }
                            )
                    }
                }
                .frame(width: CGFloat(dailyCounts.count) * 30, height: 160)
            }
            .defaultScrollAnchor(.trailing)
        }
    }

    // MARK: - Header variants

    @ViewBuilder private var weekSummaryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK")
                    .font(.theme(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(weekTotal) answers")
                        .font(.theme(.title2, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            Spacer()
        }
        .transition(.opacity)
    }

    @ViewBuilder private func selectedDayHeader(_ data: DailyCount) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(data.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.theme(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(data.reviewAttempts) answers")
                        .font(.theme(.title2, weight: .bold))
                    HStack(spacing: 10) {
                        Text("\(data.correctAnswers) correct")
                        Text("\(data.wordsIntroduced) new")
                        Text("\(data.movedToMastered) mastered")
                    }
                    .font(.theme(.caption))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Cumulative Progress Chart

private struct CumulativeProgressChartView: View {
    let entries: [CumulativeProgressEntry]
    let targetLevel: String
    let targetCount: Int
    let benchmarks: [(level: String, count: Int)]
    let projection: CoverageProjection?
    
    @State private var selectedDate: Date?
    
    private var yMax: Double {
        let maxCount = entries.last?.count ?? 0
        return Double(max(1, max(maxCount, targetCount))) * 1.1
    }

    private var projectedEntries: [ProjectedCoverageEntry] {
        guard let projection else { return [] }
        return [
            ProjectedCoverageEntry(date: projection.startDate, count: projection.currentCount),
            ProjectedCoverageEntry(date: projection.projectedDate, count: projection.targetCount),
        ]
    }

    private var currentCount: Int {
        projection?.currentCount ?? entries.last?.count ?? 0
    }

    private var chartStartDate: Date? {
        entries.first?.date ?? projectedEntries.first?.date
    }

    private var chartEndDate: Date? {
        projectedEntries.last?.date ?? entries.last?.date
    }

    private var chartSpanInMonths: Int {
        guard let chartStartDate, let chartEndDate else { return 0 }
        return Calendar.current.dateComponents([.month], from: chartStartDate, to: chartEndDate).month ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = selectedDate, let entry = entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                    .font(.theme(.caption2))
                    .foregroundStyle(.secondary)
                Text("\(entry.count) introduced")
                    .font(.theme(.headline, weight: .semibold))
            } else {
                Text("\(currentCount) / \(targetCount)")
                    .font(.theme(.headline, weight: .semibold))
                if let projection {
                    Text("\(projection.sampleDays)-day pace: \(dailyRateLabel(projection.recentDailyRate))/day · \(projection.remainingCount) left → \(projection.projectedDate, format: .dateTime.month(.abbreviated).day().year())")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                } else if currentCount >= targetCount {
                    Text("All vocabulary through \(targetLevel) is complete.")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No new words added in the last \(StatsViewModel.coverageProjectionSampleDays) days.")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            if entries.isEmpty && projection == nil {
                Text("No words introduced yet.")
                    .font(.theme(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                Chart {
                    ForEach(entries) { entry in
                        LineMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Introduced", entry.count),
                            series: .value("Line", "Actual")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Theme.primary)
                    }

                    ForEach(projectedEntries) { entry in
                        LineMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Introduced", entry.count),
                            series: .value("Line", "Plan")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(Theme.primary)
                    }

                    ForEach(benchmarks, id: \.level) { benchmark in
                        RuleMark(y: .value("Level", benchmark.count))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .annotation(position: .top, alignment: .leading) {
                                Text(benchmark.level)
                                    .font(.theme(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                    }

                    if let selectedDate {
                        RuleMark(x: .value("Selected", selectedDate, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                }
                .chartYScale(domain: 0...yMax)
                .chartXAxis {
                    if chartSpanInMonths <= 12 {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    } else if chartSpanInMonths <= 36 {
                        AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .year)) { _ in
                            AxisValueLabel(format: .dateTime.year())
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let plotArea = geometry[plotFrame]
                                        let xPosition = value.location.x - plotArea.origin.x
                                        if let tapped: Date = proxy.value(atX: xPosition) {
                                            selectedDate = Calendar.current.startOfDay(for: tapped)
                                        }
                                    }
                                    .onEnded { _ in selectedDate = nil }
                            )
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private func dailyRateLabel(_ rate: Double) -> String {
        String(format: rate < 1 ? "%.2f" : "%.1f", rate)
    }
}

private struct ProjectedCoverageEntry: Identifiable {
    let date: Date
    let count: Int

    var id: String { "\(date.timeIntervalSince1970)-\(count)" }
}

// MARK: - Supporting views

// MARK: - Existing rows

private struct ProgressRow: View {
    let label: String
    let count: Int
    let total: Int?
    let color: Color

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .font(.theme(.body, weight: .semibold))
                .foregroundStyle(color)
            if let total {
                Text("/ \(total)")
                    .foregroundStyle(.secondary)
                    .font(.theme(.caption))
            }
        }
    }
}

private struct LevelProgressRow: View {
    let stats: LevelStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stats.level)
                    .font(.theme(.body, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                Text("\(stats.mastered) M · \(stats.production) P · \(stats.recognition) R / \(stats.total)")
                    .foregroundStyle(.secondary)
                    .font(.theme(.caption))
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("\(stats.mastered) mastered, \(stats.production) production, \(stats.recognition) recognition, \(stats.total) total")
            }
            GeometryReader { geo in
                let width = geo.size.width
                let total = max(1, stats.total)
                let masteredWidth = width * CGFloat(stats.mastered) / CGFloat(total)
                let productionWidth = width * CGFloat(stats.production) / CGFloat(total)
                let recognitionWidth = width * CGFloat(stats.recognition) / CGFloat(total)
                let remainingWidth = max(0, width - masteredWidth - productionWidth - recognitionWidth)

                HStack(spacing: 0) {
                    Rectangle().fill(Theme.masteredBar).frame(width: masteredWidth)
                    Rectangle().fill(Theme.production).frame(width: productionWidth)
                    Rectangle().fill(Theme.recognition).frame(width: recognitionWidth)
                    Rectangle().fill(Theme.chipBackground).frame(width: remainingWidth)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.barCornerRadius, style: .continuous))
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

private struct TenseProgressRow: View {
    let stat: TenseStat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.tense.capitalized).font(.theme(.body, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%% recent · %@", stat.score * 100, attemptsLabel))
                    .foregroundStyle(.secondary)
                    .font(.theme(.caption))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.barCornerRadius, style: .continuous).fill(Theme.chipBackground)
                    
                    let width = geo.size.width * CGFloat(max(0, min(1, stat.score)))
                    RoundedRectangle(cornerRadius: Theme.barCornerRadius, style: .continuous)
                        .fill(Theme.primary)
                        .frame(width: width)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }

    private var attemptsLabel: String {
        "\(stat.attempts) \(stat.attempts == 1 ? "attempt" : "attempts")"
    }
}

import SwiftUI
import Charts

struct StatsView: View {
    @State private var vm = StatsViewModel()

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        NavigationStack {
            List {
                Section("Activity") {
                    DailyActivityChart(
                        dailyCounts: vm.dailyWordCounts(),
                        weekTotal: vm.thisWeekWordCount
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                }

                Section("CEFR Coverage") {
                    Picker("Target Level", selection: Binding(
                        get: { vm.targetLevel },
                        set: { vm.targetLevel = $0 }
                    )) {
                        Text("None").tag("None")
                        Text("A1").tag("A1")
                        Text("A2").tag("A2")
                        Text("B1").tag("B1")
                        Text("B2").tag("B2")
                        Text("C1").tag("C1")
                        Text("C2").tag("C2")
                    }

                    if vm.targetLevel != "None" {
                        CumulativeProgressChartView(
                            entries: vm.cumulativeProgressData(),
                            targetLevel: vm.targetLevel,
                            targetCount: vm.targetWordCount(for: vm.targetLevel),
                            benchmarks: vm.benchmarks(for: vm.targetLevel)
                        )
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    } else {
                        Text("Choose a CEFR range to see the words you have introduced within that range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }

                Section("Overall") {
                    ProgressRow(label: "Mastered",              count: vm.mastered,    total: vm.total, color: Theme.primaryDark)
                    ProgressRow(label: "Production (EN → IT)",  count: vm.production,  total: vm.total, color: Theme.primary)
                    ProgressRow(label: "Recognition (IT → EN)", count: vm.recognition, total: vm.total, color: Theme.primaryLight)
                    ProgressRow(label: "Not started",           count: vm.notStarted,  total: vm.total, color: .gray)
                    ProgressRow(label: "Skipped",               count: vm.skipped,     total: nil,      color: .secondary)
                }
                
                if !vm.tenseStats.isEmpty {
                    Section("Tense Proficiency") {
                        ForEach(vm.tenseStats, id: \.tense) { stat in
                            TenseProgressRow(stat: stat)
                        }
                    }
                }

                Section("By Level") {
                    ForEach(levels, id: \.self) { level in
                        LevelProgressRow(stats: vm.statsFor(level: level))
                    }
                }

                if !vm.customCategories.isEmpty {
                    Section("By Category") {
                        ForEach(vm.customCategories, id: \.self) { category in
                            LevelProgressRow(stats: vm.statsFor(level: category))
                        }
                    }
                }
            }
            .navigationTitle("Progress")
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayStr = formatter.string(from: Date())
        return DailyCount(dateString: todayStr)
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
                            y: .value("Review answers", entry.reviewAttempts)
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
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("").font(.system(size: 8))
                                    }
                                    Text(date, format: .dateTime.weekday(.narrow))
                                        .font(.theme(.caption2))
                                        .fontWeight(Calendar.current.isDateInToday(date) ? .bold : .regular)
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
                                        let plotArea = geometry[proxy.plotAreaFrame]
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
                Text("REVIEW ANSWERS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(weekTotal)")
                        .font(.theme(.title2, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    Text("this week")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Each submitted answer counts once")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    @ViewBuilder private func selectedDayHeader(_ data: DailyCount) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(data.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(data.reviewAttempts)")
                        .font(.theme(.title2, weight: .bold))
                    if data.hasDetailedMetrics {
                        HStack(spacing: 10) {
                            Text("\(data.correctAnswers) correct")
                            Text("\(data.wordsIntroduced) introduced")
                            Text("\(data.movedToMastered) mastered")
                        }
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                    }
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
    
    @State private var selectedDate: Date?
    
    private var yMax: Double {
        let maxCount = entries.last?.count ?? 0
        return Double(max(1, max(maxCount, targetCount))) * 1.1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = selectedDate, let entry = entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(entry.count) words introduced")
                    .font(.headline)
            } else {
                Text("\(entries.last?.count ?? 0) / \(targetCount) words introduced")
                    .font(.headline)
                Text("Counts only words labelled A1 through \(targetLevel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("No words in this CEFR range have been introduced yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                Chart {
                    ForEach(entries) { entry in
                        LineMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Words introduced", entry.count)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Theme.primary)
                    }

                    ForEach(benchmarks, id: \.level) { benchmark in
                        RuleMark(y: .value("Level", benchmark.count))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .annotation(position: .top, alignment: .leading) {
                                Text(benchmark.level)
                                    .font(.caption2)
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
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let plotArea = geometry[proxy.plotAreaFrame]
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
                .foregroundStyle(color)
                .fontWeight(.semibold)
            if let total {
                Text("/ \(total)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private struct LevelProgressRow: View {
    let stats: LevelStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stats.level).fontWeight(.semibold)
                Spacer()
                Text("\(stats.mastered) mastered · \(stats.production) production · \(stats.recognition) recognition / \(stats.total)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            GeometryReader { geo in
                let width = geo.size.width
                let total = max(1, stats.total)
                let masteredWidth = width * CGFloat(stats.mastered) / CGFloat(total)
                let productionWidth = width * CGFloat(stats.production) / CGFloat(total)
                let recognitionWidth = width * CGFloat(stats.recognition) / CGFloat(total)
                let remainingWidth = max(0, width - masteredWidth - productionWidth - recognitionWidth)

                HStack(spacing: 0) {
                    Rectangle().fill(Theme.primaryDark).frame(width: masteredWidth)
                    Rectangle().fill(Theme.primary).frame(width: productionWidth)
                    Rectangle().fill(Theme.primaryLight).frame(width: recognitionWidth)
                    Rectangle().fill(Color(.systemGray5)).frame(width: remainingWidth)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                Text(stat.tense.capitalized).fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.0f%% recent form · %@", stat.score * 100, attemptsLabel))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5))
                    
                    let width = geo.size.width * CGFloat(max(0, min(1, stat.score)))
                    RoundedRectangle(cornerRadius: 4)
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

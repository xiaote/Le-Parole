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
                        goal: vm.dailyGoal,
                        weekTotal: vm.thisWeekWordCount
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                }

                let entries = vm.cumulativeProgressData()
                if !entries.isEmpty {
                    Section("Target Projection") {
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
                                entries: entries,
                                targetLevel: vm.targetLevel,
                                vm: vm
                            )
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                        } else {
                            Text("Select a target CEFR level above to calculate when you will reach it based on your recent velocity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
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

private struct DailyEntry: Identifiable {
    let id = UUID()
    let date: Date
    let stage: String
    let count: Int
}

private struct DailyActivityChart: View {
    let dailyCounts: [DailyCount]
    let goal: Int
    let weekTotal: Int

    @State private var selectedDate: Date?

    private var entries: [DailyEntry] {
        dailyCounts.flatMap { day in [
            DailyEntry(date: day.date, stage: "Recognizing", count: day.recognition),
            DailyEntry(date: day.date, stage: "Reviewing",   count: day.production),
            DailyEntry(date: day.date, stage: "Mastered",    count: day.mastered),
        ]}
    }

    private var yMax: Double {
        let maxTotal = dailyCounts.map(\.total).max() ?? 0
        return Double(max(goal + 2, maxTotal + 2))
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
        return DailyCount(dateString: todayStr, recognition: 0, production: 0, mastered: 0)
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

            // Scrollable stacked bar chart
            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(entries) { entry in
                        BarMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("Words", entry.count)
                        )
                        .foregroundStyle(by: .value("Stage", entry.stage))
                        .opacity(
                            selectedDate == nil ||
                            Calendar.current.startOfDay(for: entry.date) == selectedDate
                                ? 1.0 : 0.35
                        )
                        .cornerRadius(3, style: .continuous)
                    }

                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.4))

                    if let sel = selectedDate {
                        RuleMark(x: .value("Selected", sel, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                }
                .chartForegroundStyleScale([
                    "Recognizing": Theme.primaryLight,
                    "Reviewing":   Theme.primary,
                    "Mastered":    Theme.primaryDark,
                ])
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
                    Color.clear.contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if let tapped: Date = proxy.value(atX: value.location.x) {
                                        let day = Calendar.current.startOfDay(for: tapped)
                                        if selectedDate != day { selectedDate = day }
                                    }
                                }
                                .onEnded { _ in selectedDate = nil }
                        )
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
                Text("WORDS REVIEWED")
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
            Text("Goal: \(goal)/day")
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
                    Text("\(data.total)")
                        .font(.theme(.title2, weight: .bold))
                    HStack(spacing: 10) {
                        MiniStageCount(color: Theme.primaryLight, count: data.recognition)
                        MiniStageCount(color: Theme.primary,   count: data.production)
                        MiniStageCount(color: Theme.primaryDark,  count: data.mastered)
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
    let vm: StatsViewModel
    
    @State private var selectedDate: Date?
    
    private var yMax: Double {
        let maxCount = entries.last?.count ?? 0
        let targetCount = benchmarks.last?.count ?? 0
        return Double(max(maxCount, targetCount)) * 1.1
    }
    
    private var benchmarks: [(level: String, count: Int)] {
        let targetLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
        var total = 0
        var results: [(String, Int)] = []
        for lvl in targetLevels {
            total += vm.statsFor(level: lvl).total
            results.append((lvl, total))
            if lvl == targetLevel { break }
        }
        return results
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = selectedDate, let entry = entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(entry.count) words")
                            .font(.headline)
                        if entry.isProjected {
                            Text("Projected")
                                .font(.caption)
                                .foregroundStyle(Theme.primary)
                        }
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Target: \(targetLevel)")
                            .font(.headline)
                        if let last = entries.last, last.isProjected {
                            Text("Projected by \(last.date, format: .dateTime.month(.abbreviated).day().year())")
                                .font(.caption)
                                .foregroundStyle(Theme.primary)
                        } else {
                            Text("Learn new words to generate a projection!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Chart {
                ForEach(entries) { entry in
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Words", entry.count),
                        series: .value("Type", entry.isProjected ? "Projected" : "Historical")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: entry.isProjected ? [5, 5] : []))
                    .foregroundStyle(Theme.primary)
                }
                
                ForEach(benchmarks, id: \.0) { benchmark in
                    RuleMark(y: .value("Level", benchmark.1))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .annotation(position: .top, alignment: .leading) {
                            Text(benchmark.0)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                
                if let sel = selectedDate {
                    RuleMark(x: .value("Selected", sel, unit: .day))
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
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let tapped: Date = proxy.value(atX: value.location.x) {
                                    let day = Calendar.current.startOfDay(for: tapped)
                                    selectedDate = day
                                }
                            }
                            .onEnded { _ in selectedDate = nil }
                    )
            }
            .frame(height: 200)
        }
    }
}

// MARK: - Supporting views

private struct MiniStageCount: View {
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
        }
    }
}

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
                Text("\(stats.mastered) mastered / \(stats.production) reviewing / \(stats.total) total")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5))
                    
                    let totalProgressWidth = stats.total > 0 ? geo.size.width * CGFloat(stats.mastered + stats.production) / CGFloat(stats.total) : 0
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.primary)
                        .frame(width: totalProgressWidth)
                        
                    let masteredWidth = stats.total > 0 ? geo.size.width * CGFloat(stats.mastered) / CGFloat(stats.total) : 0
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.primaryDark)
                        .frame(width: masteredWidth)
                }
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
                Text(String(format: "%.0f%% Mastery", stat.score * 100))
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
}

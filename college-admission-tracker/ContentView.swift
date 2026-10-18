import SwiftUI
import Observation

struct ApplicationWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var opens: Date
    var closes: Date
    var results: Date

    init(id: UUID = UUID(), opens: Date, closes: Date, results: Date) {
        self.id = id
        self.opens = opens
        self.closes = closes
        self.results = results
    }
}

struct SchoolApplication: Identifiable, Codable, Equatable {
    let id: UUID
    var schoolName: String
    var programName: String
    var facultyName: String
    var windows: [ApplicationWindow]

    init(
        id: UUID = UUID(),
        schoolName: String,
        programName: String,
        facultyName: String,
        windows: [ApplicationWindow]
    ) {
        self.id = id
        self.schoolName = schoolName
        self.programName = programName
        self.facultyName = facultyName
        self.windows = windows
    }
}

enum ApplicationStatus: Equatable {
    case waiting
    case admissionsOpen
    case waitingForResult
    case resultsOut

    var title: LocalizedStringKey {
        switch self {
        case .waiting:
            "Waiting"
        case .admissionsOpen:
            "Admissions open"
        case .waitingForResult:
            "Waiting for result"
        case .resultsOut:
            "Results out"
        }
    }

    var color: Color {
        switch self {
        case .waiting:
            .secondary
        case .admissionsOpen:
            .blue
        case .waitingForResult:
            .cyan
        case .resultsOut:
            .green
        }
    }
}

struct ApplicationTimeline {
    let status: ApplicationStatus
    let countdown: String
    let eventName: String
    let remainingDays: Int?

    var isUrgentClosing: Bool {
        status == .admissionsOpen && (remainingDays ?? .max) <= 7
    }

    init(window: ApplicationWindow, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let opens = calendar.startOfDay(for: window.opens)
        let closes = calendar.startOfDay(for: window.closes)
        let results = calendar.startOfDay(for: window.results)

        if today < opens {
            status = .waiting
            remainingDays = Self.days(from: today, to: opens, calendar: calendar)
            eventName = "opens"
        } else if today <= closes {
            status = .admissionsOpen
            remainingDays = Self.days(from: today, to: closes, calendar: calendar)
            eventName = "closes"
        } else if today < results {
            status = .waitingForResult
            remainingDays = Self.days(from: today, to: results, calendar: calendar)
            eventName = "results"
        } else {
            status = .resultsOut
            remainingDays = nil
            eventName = ""
        }

        if let remainingDays {
            countdown = remainingDays == 0 ? "Today" : "D-\(remainingDays)"
        } else {
            countdown = "Released"
        }
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }
}

@MainActor
@Observable
final class ApplicationStore {
    private static let storageKey = "collegeApplications"
    private(set) var schools: [SchoolApplication] = []

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SchoolApplication].self, from: data) else {
            return
        }
        schools = decoded
    }

    func save(_ application: SchoolApplication) {
        if let index = schools.firstIndex(where: { $0.id == application.id }) {
            schools[index] = application
        } else {
            schools.append(application)
        }
        schools.sort {
            ($0.windows.map(\.opens).min() ?? .distantFuture)
                < ($1.windows.map(\.opens).min() ?? .distantFuture)
        }
        persist()
    }

    func delete(id: SchoolApplication.ID) {
        schools.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(schools) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

struct ContentView: View {
    @State private var store = ApplicationStore()
    @State private var editor: SchoolApplication?

    var body: some View {
        Group {
            if let editor {
                SchoolEditor(application: editor) { savedSchool in
                    store.save(savedSchool)
                    self.editor = nil
                } onCancel: {
                    self.editor = nil
                }
                .id(editor.id)
            } else {
                ApplicationsList(
                    schools: store.schools,
                    onAdd: { self.editor = Self.blankApplication() },
                    onEdit: { self.editor = $0 },
                    onDelete: { store.delete(id: $0) }
                )
            }
        }
        .frame(
            width: editor == nil ? 405 : 500,
            height: editor == nil ? compactListHeight : 530
        )
    }

    private var compactListHeight: CGFloat {
        guard !store.schools.isEmpty else { return 220 }

        let rowsHeight = store.schools.reduce(CGFloat.zero) { height, school in
            let windowCount = max(1, school.windows.count)
            let timelinesHeight = CGFloat(windowCount * 24 + max(0, windowCount - 1) * 4)
            return height + max(32, timelinesHeight) + 14
        }
        let separatorsHeight = CGFloat(max(0, store.schools.count - 1))
        return min(480, 97 + rowsHeight + separatorsHeight)
    }

    private static func blankApplication() -> SchoolApplication {
        SchoolApplication(
            schoolName: "",
            programName: "",
            facultyName: "",
            windows: [newWindow()]
        )
    }

    private static func newWindow() -> ApplicationWindow {
        let calendar = Calendar.current
        let opens = calendar.startOfDay(for: .now)
        let closes = calendar.date(byAdding: .day, value: 14, to: opens) ?? opens
        let results = calendar.date(byAdding: .day, value: 30, to: closes) ?? closes
        return ApplicationWindow(opens: opens, closes: closes, results: results)
    }
}

struct ApplicationsList: View {
    let schools: [SchoolApplication]
    let onAdd: () -> Void
    let onEdit: (SchoolApplication) -> Void
    let onDelete: (SchoolApplication.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(onAdd: onAdd)

            Divider()

            if schools.isEmpty {
                EmptyApplicationsView(onAdd: onAdd)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(schools.enumerated(), id: \.element.id) { index, school in
                            VStack(spacing: 0) {
                                SchoolRow(
                                    school: school,
                                    onEdit: { onEdit(school) },
                                    onDelete: { onDelete(school.id) }
                                )
                                if index < schools.count - 1 {
                                    Divider()
                                        .padding(.leading, 10)
                                }
                            }
                        }
                    }
                }
            }

            Divider()
            AppFooter()
        }
    }
}

struct AppHeader: View {
    let onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Applications")
                    .font(.headline)
                Text("College admissions timeline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Add a school")
        }
        .padding(14)
    }
}

struct EmptyApplicationsView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No applications yet", systemImage: "graduationcap")
        } description: {
            Text("Add a school and up to three application windows.")
        } actions: {
            Button("Add School", action: onAdd)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SchoolRow: View {
    let school: SchoolApplication
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .center, spacing: 2) {
                SchoolIdentity(
                    schoolName: school.schoolName,
                    programName: school.programName,
                    facultyName: school.facultyName
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(school.windows.enumerated()), id: \.element.id) { index, window in
                        WindowStatus(
                            number: index + 1,
                            totalWindows: school.windows.count,
                            timeline: ApplicationTimeline(window: window)
                        )
                    }
                }
                .frame(width: 128, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(Array(school.windows.enumerated()), id: \.element.id) { _, window in
                        CountdownView(timeline: ApplicationTimeline(window: window))
                    }
                }
                .frame(width: 55, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .offset(y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", action: onEdit)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct SchoolIdentity: View {
    let schoolName: String
    let programName: String
    let facultyName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(schoolName)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(programName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            Text(facultyName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct WindowStatus: View {
    let number: Int
    let totalWindows: Int
    let timeline: ApplicationTimeline

    var body: some View {
        HStack(spacing: 4) {
            PulsingStatusDot(
                color: timeline.status.color,
                shouldPulse: timeline.status == .admissionsOpen || timeline.status == .resultsOut
            )
            Text(timeline.status.title)
                .font(.system(size: 12.5))
                .foregroundStyle(timeline.status.color)
                .lineLimit(1)
            if totalWindows > 1 {
                Text(Self.roman(number))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 24)
    }

    private static func roman(_ number: Int) -> String {
        switch number {
        case 1: "(I)"
        case 2: "(II)"
        default: "(III)"
        }
    }
}

struct PulsingStatusDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGlowing = false

    let color: Color
    let shouldPulse: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(shouldPulse && isGlowing ? 1.45 : 1)
            .opacity(shouldPulse ? (isGlowing ? 1 : 0.5) : 1)
            .shadow(
                color: shouldPulse ? color.opacity(isGlowing ? 1 : 0.35) : .clear,
                radius: shouldPulse && isGlowing ? 7 : 1
            )
            .padding(.trailing, 2)
            .onAppear {
                guard shouldPulse, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    isGlowing = true
                }
            }
            .accessibilityHidden(true)
    }
}

struct CountdownView: View {
    let timeline: ApplicationTimeline

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(timeline.countdown)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(timeline.isUrgentClosing ? .red : .primary)
                .contentTransition(.numericText())
            if !timeline.eventName.isEmpty {
                Text(timeline.eventName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 24)
    }
}

struct AppFooter: View {
    @State private var quote = "Small steps still move you forward."

    private static let quotes = [
        "Small steps still move you forward.",
        "Your future is built one choice at a time.",
        "Keep going; clarity follows action.",
        "Preparation turns hope into possibility.",
        "A brave beginning is already progress.",
        "Trust the work you have put in.",
        "One deadline at a time.",
        "The next chapter is worth the effort.",
        "Consistency carries dreams forward.",
        "Make today count toward tomorrow."
    ]

    var body: some View {
        HStack {
            Text(quote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .help(quote)
            Spacer(minLength: 8)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .onAppear {
            selectNextQuote()
        }
    }

    private func selectNextQuote() {
        let alternatives = Self.quotes.filter { $0 != quote }
        quote = alternatives.randomElement() ?? quote
    }
}

struct SchoolEditor: View {
    @State private var application: SchoolApplication
    let onSave: (SchoolApplication) -> Void
    let onCancel: () -> Void

    init(
        application: SchoolApplication,
        onSave: @escaping (SchoolApplication) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _application = State(initialValue: application)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(application.schoolName.isEmpty ? "Add School" : "Edit School")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    application.windows.sort { $0.opens < $1.opens }
                    onSave(application)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(16)

            Divider()

            Form {
                Section("School") {
                    TextField("School name", text: $application.schoolName)
                    TextField("Program", text: $application.programName)
                    TextField("Faculty or school", text: $application.facultyName)
                }

                Section {
                    ForEach($application.windows) { $window in
                        ApplicationWindowEditor(
                            number: application.windows.firstIndex(where: { $0.id == window.id }).map { $0 + 1 } ?? 1,
                            window: $window,
                            canDelete: application.windows.count > 1,
                            onDelete: {
                                application.windows.removeAll { $0.id == window.id }
                            }
                        )
                    }

                    if application.windows.count < 3 {
                        Button {
                            addWindow()
                        } label: {
                            Label("Add application window", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text("Application Windows")
                        Spacer()
                        Text("\(application.windows.count) of 3")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 530)
        .interactiveDismissDisabled()
    }

    private var isValid: Bool {
        !application.schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !application.programName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && application.windows.allSatisfy { $0.opens <= $0.closes && $0.closes <= $0.results }
    }

    private func addWindow() {
        guard application.windows.count < 3 else { return }
        let calendar = Calendar.current
        let previous = application.windows.last
        let opens = calendar.date(byAdding: .day, value: 30, to: previous?.closes ?? .now) ?? .now
        let closes = calendar.date(byAdding: .day, value: 14, to: opens) ?? opens
        let results = calendar.date(byAdding: .day, value: 30, to: closes) ?? closes
        application.windows.append(ApplicationWindow(opens: opens, closes: closes, results: results))
    }
}

struct ApplicationWindowEditor: View {
    let number: Int
    @Binding var window: ApplicationWindow
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Window \(Self.roman(number))")
                    .font(.subheadline.bold())
                Spacer()
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this window")
                }
            }

            DatePicker("Applications open", selection: $window.opens, displayedComponents: .date)
            DatePicker("Applications close", selection: $window.closes, displayedComponents: .date)
            DatePicker("Results released", selection: $window.results, displayedComponents: .date)

            if window.opens > window.closes || window.closes > window.results {
                Label("Dates must be in chronological order.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 5)
    }

    private static func roman(_ number: Int) -> String {
        switch number {
        case 1: "I"
        case 2: "II"
        default: "III"
        }
    }
}

#Preview {
    ContentView()
}

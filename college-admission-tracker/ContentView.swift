import SwiftUI
import Observation

enum AdmissionWindowKind: String, Codable, Equatable {
    case regular
    case early
}

struct ApplicationWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: AdmissionWindowKind
    var opens: Date
    var closes: Date
    var results: Date

    init(
        id: UUID = UUID(),
        kind: AdmissionWindowKind = .regular,
        opens: Date,
        closes: Date,
        results: Date
    ) {
        self.id = id
        self.kind = kind
        self.opens = opens
        self.closes = closes
        self.results = results
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case opens
        case closes
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(AdmissionWindowKind.self, forKey: .kind) ?? .regular
        opens = try container.decode(Date.self, forKey: .opens)
        closes = try container.decode(Date.self, forKey: .closes)
        results = try container.decode(Date.self, forKey: .results)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = ApplicationStore()
    @State private var selectedSchool: SchoolApplication?
    @State private var editor: SchoolApplication?
    @State private var isContentVisible = true

    private let maximumListHeight: CGFloat

    init(maximumListHeight: CGFloat = 700) {
        self.maximumListHeight = maximumListHeight
    }

    var body: some View {
        Group {
            if let editor {
                SchoolEditor(application: editor) { savedSchool in
                    animateNavigation {
                        store.save(savedSchool)
                        selectedSchool = savedSchool
                        self.editor = nil
                    }
                } onCancel: {
                    animateNavigation {
                        self.editor = nil
                    }
                }
                .id(editor.id)
            } else if let selectedSchool {
                SchoolDetails(
                    school: selectedSchool,
                    onBack: {
                        animateNavigation {
                            self.selectedSchool = nil
                        }
                    },
                    onEdit: {
                        animateNavigation {
                            self.editor = selectedSchool
                        }
                    },
                    onDelete: {
                        animateNavigation {
                            store.delete(id: selectedSchool.id)
                            self.selectedSchool = nil
                        }
                    }
                )
                .id(selectedSchool.id)
            } else {
                ApplicationsList(
                    schools: store.schools,
                    onAdd: {
                        animateNavigation {
                            selectedSchool = nil
                            self.editor = Self.blankApplication()
                        }
                    },
                    onSelect: { school in
                        animateNavigation {
                            selectedSchool = school
                        }
                    }
                )
            }
        }
        .opacity(isContentVisible ? 1 : 0)
        .allowsHitTesting(isContentVisible)
        .frame(
            width: editor == nil ? 468 : 500,
            height: contentHeight
        )
        .clipped()
    }

    private func animateNavigation(_ updates: @escaping () -> Void) {
        guard !reduceMotion else {
            updates()
            return
        }

        withAnimation(.linear(duration: 0.06)) {
            isContentVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            updates()
            withAnimation(.linear(duration: 0.08)) {
                isContentVisible = true
            }
        }
    }

    private var contentHeight: CGFloat {
        if editor != nil {
            return 530
        }

        if let selectedSchool {
            let periodCount = CGFloat(max(1, selectedSchool.windows.count))
            let periodsHeight = periodCount * 81
            let spacingHeight = max(0, periodCount - 1) * 10
            let surroundingContentHeight: CGFloat = 134
            return min(
                maximumListHeight,
                surroundingContentHeight + periodsHeight + spacingHeight
            )
        }

        return compactListHeight
    }

    private var compactListHeight: CGFloat {
        guard !store.schools.isEmpty else { return 220 }

        let rowsHeight = store.schools.reduce(CGFloat.zero) { height, school in
            let windowCount = max(1, school.windows.count)
            let timelinesHeight = CGFloat(windowCount * 32 + max(0, windowCount - 1) * 8)
            return height + max(32, timelinesHeight) + 14
        }
        let separatorsHeight = CGFloat(max(0, store.schools.count - 1))
        return min(maximumListHeight, 97 + rowsHeight + separatorsHeight)
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
    let onSelect: (SchoolApplication) -> Void

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
                                    onSelect: { onSelect(school) }
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
            Text("Add a school, regular windows, and early admission dates.")
        } actions: {
            Button("Add School", action: onAdd)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SchoolDetails: View {
    @State private var isShowingDeleteConfirmation = false

    let school: SchoolApplication
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Back to applications")

                SchoolIdentity(
                    schoolName: school.schoolName,
                    programName: school.programName,
                    facultyName: school.facultyName
                )

                Spacer()
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(school.windows.enumerated()), id: \.element.id) { index, window in
                        AdmissionWindowDetails(
                            title: Self.title(for: window, at: index, in: school.windows),
                            window: window
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 14) {
                Spacer()

                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Delete application")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Edit application")
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
        }
        .overlay {
            if isShowingDeleteConfirmation {
                DeleteConfirmationView(
                    schoolName: school.schoolName,
                    onCancel: {
                        isShowingDeleteConfirmation = false
                    },
                    onDelete: onDelete
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: isShowingDeleteConfirmation)
    }

    private static func title(
        for window: ApplicationWindow,
        at index: Int,
        in windows: [ApplicationWindow]
    ) -> String {
        if window.kind == .early {
            return "Early Admission"
        }

        let regularWindows = windows.filter { $0.kind == .regular }
        guard regularWindows.count > 1 else {
            return "Application Window"
        }

        let regularNumber = windows[..<index].filter { $0.kind == .regular }.count + 1
        return "Application Window \(roman(regularNumber))"
    }

    private static func roman(_ number: Int) -> String {
        switch number {
        case 1: "I"
        case 2: "II"
        default: "III"
        }
    }
}

struct DeleteConfirmationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFieldFocused: Bool
    @State private var confirmationText = ""
    @State private var isBursting = false

    let schoolName: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    private let requiredText = "delete"

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            confirmationCard
                .scaleEffect(isBursting ? 1.28 : 1)
                .opacity(isBursting ? 0 : 1)
                .blur(radius: isBursting ? 10 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(progressColor)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Delete application")
                        .font(.headline)
                    Text(schoolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel")
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            Text("Type “delete” below to permanently remove this application and all of its dates.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("delete", text: $confirmationText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(progressColor.opacity(validPrefix ? 0.35 + progress * 0.55 : 0.18))
                }
                .focused($isTextFieldFocused)
                .onSubmit(confirmDeletion)

            HStack(spacing: 6) {
                Text("Press ENTER to confirm. You can’t go back.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(isComplete ? 1 : 0)

                Spacer()

                HStack(spacing: 3) {
                    ForEach(0..<requiredText.count, id: \.self) { index in
                        Capsule()
                            .fill(
                                validPrefix && index < confirmationText.count
                                    ? Color.red.opacity(0.35 + progress * 0.65)
                                    : Color.secondary.opacity(0.18)
                            )
                            .frame(width: 9, height: 3)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(height: 13)
        }
        .padding(14)
        .frame(width: 336)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(progressColor.opacity(validPrefix ? 0.16 + progress * 0.38 : 0.1))
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .keyframeAnimator(
            initialValue: CGFloat.zero,
            trigger: confirmationText
        ) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            let amount = validPrefix ? 1.5 + progress * 7 : 0
            LinearKeyframe(-amount, duration: 0.035)
            LinearKeyframe(amount, duration: 0.05)
            LinearKeyframe(-amount * 0.7, duration: 0.045)
            LinearKeyframe(amount * 0.45, duration: 0.04)
            LinearKeyframe(0, duration: 0.035)
        }
        .animation(.easeOut(duration: 0.12), value: progress)
        .animation(.easeOut(duration: 0.1), value: isComplete)
    }

    private var validPrefix: Bool {
        !confirmationText.isEmpty && requiredText.hasPrefix(confirmationText)
    }

    private var isComplete: Bool {
        confirmationText == requiredText
    }

    private var progress: Double {
        guard validPrefix else { return 0 }
        return min(1, Double(confirmationText.count) / Double(requiredText.count))
    }

    private var progressColor: Color {
        validPrefix ? .red.opacity(0.35 + progress * 0.65) : .secondary
    }

    private var fieldBackground: Color {
        validPrefix ? .red.opacity(0.04 + progress * 0.14) : .secondary.opacity(0.08)
    }

    private func confirmDeletion() {
        guard isComplete, !isBursting else { return }

        if reduceMotion {
            onDelete()
            return
        }

        withAnimation(.easeIn(duration: 0.18)) {
            isBursting = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            onDelete()
        }
    }
}

struct AdmissionWindowDetails: View {
    let title: String
    let window: ApplicationWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.bold())

            HStack(spacing: 0) {
                DateDetail(label: "Starts", date: window.opens)
                DateDetail(label: "Ends", date: window.closes)
                DateDetail(label: "Results", date: window.results)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DateDetail: View {
    let label: LocalizedStringKey
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.month(.abbreviated).day().year())
                .font(.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SchoolRow: View {
    let school: SchoolApplication
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 2) {
                SchoolIdentity(
                    schoolName: school.schoolName,
                    programName: school.programName,
                    facultyName: school.facultyName
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(school.windows.enumerated()), id: \.element.id) { index, window in
                        WindowStatus(
                            marker: Self.marker(
                                for: window,
                                at: index,
                                in: school.windows
                            ),
                            timeline: ApplicationTimeline(window: window)
                        )
                    }
                }
                .frame(width: 142, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
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
    }

    private static func marker(
        for window: ApplicationWindow,
        at index: Int,
        in windows: [ApplicationWindow]
    ) -> String? {
        if window.kind == .early {
            return "(Early)"
        }

        let regularWindows = windows.filter { $0.kind == .regular }
        guard regularWindows.count > 1 else { return nil }
        let regularNumber = windows[..<index].filter { $0.kind == .regular }.count + 1
        return "(\(roman(regularNumber)))"
    }

    private static func roman(_ number: Int) -> String {
        switch number {
        case 1: "I"
        case 2: "II"
        default: "III"
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
    let marker: String?
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
            if let marker {
                Text(marker)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 32)
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
        VStack(alignment: .trailing, spacing: -3) {
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
        .frame(height: 32)
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
                            title: Self.title(for: window, in: application.windows),
                            window: $window,
                            canDelete: application.windows.count > 1,
                            onDelete: {
                                application.windows.removeAll { $0.id == window.id }
                            }
                        )
                    }

                    HStack {
                        if regularWindowCount < 3 {
                            Button {
                                addWindow(kind: .regular)
                            } label: {
                                Label("Add application window", systemImage: "plus")
                            }
                        }

                        if !hasEarlyAdmission {
                            Button {
                                addWindow(kind: .early)
                            } label: {
                                Label("Add early admission", systemImage: "plus")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Admission Periods")
                        Spacer()
                        Text("\(regularWindowCount) regular")
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

    private var regularWindowCount: Int {
        application.windows.filter { $0.kind == .regular }.count
    }

    private var hasEarlyAdmission: Bool {
        application.windows.contains { $0.kind == .early }
    }

    private func addWindow(kind: AdmissionWindowKind) {
        guard kind == .early ? !hasEarlyAdmission : regularWindowCount < 3 else { return }

        let calendar = Calendar.current
        let opens: Date
        if kind == .early {
            let earliestOpening = application.windows.map(\.opens).min() ?? .now
            opens = calendar.date(byAdding: .day, value: -30, to: earliestOpening) ?? earliestOpening
        } else {
            let latestClosing = application.windows.map(\.closes).max() ?? .now
            opens = calendar.date(byAdding: .day, value: 30, to: latestClosing) ?? latestClosing
        }

        let closes = calendar.date(byAdding: .day, value: 14, to: opens) ?? opens
        let results = calendar.date(byAdding: .day, value: 30, to: closes) ?? closes
        application.windows.append(
            ApplicationWindow(kind: kind, opens: opens, closes: closes, results: results)
        )
        application.windows.sort { $0.opens < $1.opens }
    }

    private static func title(
        for window: ApplicationWindow,
        in windows: [ApplicationWindow]
    ) -> String {
        guard window.kind == .regular else { return "Early Admission" }
        let regularWindows = windows.filter { $0.kind == .regular }
        guard regularWindows.count > 1,
              let index = regularWindows.firstIndex(where: { $0.id == window.id }) else {
            return "Application Window"
        }
        return "Application Window \(roman(index + 1))"
    }

    private static func roman(_ number: Int) -> String {
        switch number {
        case 1: "I"
        case 2: "II"
        default: "III"
        }
    }
}

struct ApplicationWindowEditor: View {
    let title: String
    @Binding var window: ApplicationWindow
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
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
}

#Preview {
    ContentView()
}

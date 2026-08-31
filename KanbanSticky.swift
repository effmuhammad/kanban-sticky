import AppKit
import SwiftUI

enum TaskStatus: String, CaseIterable, Codable, Identifiable {
    case todo = "Todo"
    case progress = "Progress"
    case done = "Done"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .todo: return "circle"
        case .progress: return "clock"
        case .done: return "checkmark.circle.fill"
        }
    }
}

struct KanbanTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var status: TaskStatus
    var createdAt = Date()
    var startDate: Date?
    var endDate: Date?
    var project: String? = nil
}

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [KanbanTask] = [] {
        didSet { save() }
    }

    private let storageKey = "kanbanSticky.tasks.v1"
    private let projectStorageKey = "kanbanSticky.projects.v1"
    @Published var projectCatalog: [String] = [] {
        didSet { UserDefaults.standard.set(projectCatalog, forKey: projectStorageKey) }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([KanbanTask].self, from: data) {
            tasks = decoded
        } else {
            tasks = [
                KanbanTask(title: "Review rencana hari ini", status: .todo),
                KanbanTask(title: "Kerjakan prioritas utama", status: .progress),
                KanbanTask(title: "Setup Kanban Sticky", status: .done)
            ]
        }
        projectCatalog = UserDefaults.standard.stringArray(forKey: projectStorageKey) ?? []
        projectCatalog = Array(Set(projectCatalog + tasks.compactMap { $0.project })).sorted()
    }

    func add(
        _ title: String,
        to status: TaskStatus,
        project: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tasks.insert(
                KanbanTask(
                    title: cleanTitle,
                    status: status,
                    startDate: startDate,
                    endDate: normalizedEndDate(start: startDate, end: endDate),
                    project: project?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : project?.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                at: 0
            )
        }
    }

    private func normalizedEndDate(start: Date?, end: Date?) -> Date? {
        guard let start, let end else { return end }
        return max(start, end)
    }

    func move(_ task: KanbanTask, to status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            tasks[index].status = status
        }
    }

    /// Repositions a card within its current column. Dragging upward places it
    /// at the top; dragging downward places it at the bottom.
    func reorder(_ task: KanbanTask, toBeginning: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let status = tasks[index].status
        let columnIndices = tasks.indices.filter { tasks[$0].status == status }
        guard columnIndices.count > 1,
              let first = columnIndices.first,
              let last = columnIndices.last,
              index != (toBeginning ? first : last) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            let item = tasks.remove(at: index)
            let remaining = tasks.indices.filter { tasks[$0].status == status }
            if toBeginning, let destination = remaining.first {
                tasks.insert(item, at: destination)
            } else if let destination = remaining.last {
                tasks.insert(item, at: destination + 1)
            } else {
                tasks.append(item)
            }
        }
    }

    func swapAdjacent(_ task: KanbanTask, movingUp: Bool) {
        guard let currentIndex = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let status = tasks[currentIndex].status
        let columnIndices = tasks.indices.filter { tasks[$0].status == status }
        guard let position = columnIndices.firstIndex(of: currentIndex) else { return }
        let targetPosition = movingUp ? position - 1 : position + 1
        guard columnIndices.indices.contains(targetPosition) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            tasks.swapAt(currentIndex, columnIndices[targetPosition])
        }
    }

    func remove(_ task: KanbanTask) {
        withAnimation(.easeOut(duration: 0.18)) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    func setSchedule(for task: KanbanTask, startDate: Date?, endDate: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tasks[index].startDate = startDate
            tasks[index].endDate = endDate
        }
    }

    func rename(_ task: KanbanTask, to newTitle: String) {
        let cleanTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].title = cleanTitle
    }

    func setProject(for task: KanbanTask, project: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].project = project?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : project
    }

    func count(for status: TaskStatus) -> Int {
        tasks.filter { $0.status == status }.count
    }

    var projects: [String] {
        projectCatalog
    }

    func addProject(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !projectCatalog.contains(clean) else { return }
        projectCatalog.append(clean); projectCatalog.sort()
    }

    func renameProject(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, old != clean, !projectCatalog.contains(clean) else { return }
        projectCatalog = projectCatalog.map { $0 == old ? clean : $0 }.sorted()
        for index in tasks.indices where tasks[index].project == old { tasks[index].project = clean }
    }

    func deleteProject(_ name: String) {
        projectCatalog.removeAll { $0 == name }
        for index in tasks.indices where tasks[index].project == name { tasks[index].project = nil }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private enum NoteTheme: String, CaseIterable, Identifiable {
    case ocean, honey, mint, berry
    var id: String { rawValue }

    var name: String {
        switch self {
        case .ocean: return "Ocean"
        case .honey: return "Honey"
        case .mint: return "Mint"
        case .berry: return "Berry"
        }
    }

    var background: Color {
        switch self {
        case .ocean: return Color(red: 0.035, green: 0.28, blue: 0.40)
        case .honey: return Color(red: 0.91, green: 0.68, blue: 0.20)
        case .mint: return Color(red: 0.12, green: 0.48, blue: 0.40)
        case .berry: return Color(red: 0.45, green: 0.18, blue: 0.39)
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @AppStorage("kanbanSticky.selectedStatus") private var selectedRaw = TaskStatus.todo.rawValue
    @AppStorage("kanbanSticky.theme") private var themeRaw = NoteTheme.ocean.rawValue
    @AppStorage("kanbanSticky.transparentBackground") private var transparentBackground = false
    @AppStorage("kanbanSticky.selectedProject") private var selectedProjectRaw = ""
    @AppStorage("kanbanSticky.showNotes") private var showNotes = false
    @AppStorage("kanbanSticky.notesText") private var notesText = ""
    @State private var newTask = ""
    @State private var newTaskProject = ""
    @State private var newTaskHasStartDate = false
    @State private var newTaskHasEndDate = false
    @State private var newTaskStartDate = Date()
    @State private var newTaskEndDate = Date()
    @State private var showingNewTaskSchedule = false
    @State private var showingProjectManager = false
    @State private var showingTaskEditor = false
    @State private var taskEditorStatus: TaskStatus = .todo
    @State private var notesEditing = false
    @State private var notesSearch = ""
    @State private var showNotesSearch = false
    @State private var draggedTask: KanbanTask?
    @State private var dragLocation: CGPoint?
    @State private var isFolded = false
    @State private var expandedWindowHeight: CGFloat = 560
    @FocusState private var inputFocused: Bool

    private var selectedStatus: TaskStatus {
        get { TaskStatus(rawValue: selectedRaw) ?? .todo }
        nonmutating set { selectedRaw = newValue.rawValue }
    }

    private var theme: NoteTheme {
        NoteTheme(rawValue: themeRaw) ?? .ocean
    }

    private var visibleTasks: [KanbanTask] {
        store.tasks.filter { $0.status == selectedStatus && projectMatches($0) }
    }

    private func projectMatches(_ task: KanbanTask) -> Bool {
        selectedProjectRaw.isEmpty || task.project == selectedProjectRaw
    }

    private var completion: Double {
        guard !store.tasks.isEmpty else { return 0 }
        return Double(store.count(for: .done)) / Double(store.tasks.count)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.background.opacity(transparentBackground ? 0.42 : 1)
                VStack(spacing: 0) {
                    titleBar
                    if !isFolded {
                        HStack(spacing: 0) {
                            Group {
                                if proxy.size.width >= 720 && (!showNotes || proxy.size.width >= 980) {
                                    boardLayout
                                        .transition(.opacity)
                                } else {
                                    compactLayout
                                        .transition(.opacity)
                                }
                            }
                            if showNotes {
                                notesPanel
                                    .frame(width: proxy.size.width >= 760 ? 320 : 240)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            }
        }
        .background(Color.clear)
        .sheet(isPresented: $showingProjectManager) {
            ProjectManagerView(store: store)
        }
        .sheet(isPresented: $showingTaskEditor) {
            TaskEditorView(store: store, initialStatus: taskEditorStatus)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            statusPicker
            taskList
            composer
            footer
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "note.text")
                Text("Notes")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.15)) { showNotesSearch.toggle() } } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(showNotesSearch ? 0.2 : 0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .help(showNotesSearch ? "Sembunyikan pencarian" : "Cari notes")
                Button { showNotes = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Sembunyikan notes")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            if showNotesSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Cari notes…", text: $notesSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
            }
            WYSIWYGNotesEditor(text: $notesText, search: notesSearch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.14))
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
        }
    }

    private func noteFormatButton(_ icon: String, _ help: String, _ prefix: String) -> some View {
        Button { insertNotePrefix(prefix) } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func insertNotePrefix(_ prefix: String) {
        if notesText.isEmpty || notesText.hasSuffix("\n") { notesText += prefix }
        else { notesText += "\n" + prefix }
    }

    private struct WYSIWYGNotesEditor: NSViewRepresentable {
        @Binding var text: String
        var search: String = ""
        func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSScrollView()
            let editor = NSTextView()
            editor.delegate = context.coordinator
            editor.string = text
            editor.font = NSFont.systemFont(ofSize: 14)
            editor.textColor = .white
            editor.backgroundColor = .clear
            editor.drawsBackground = false
            editor.isRichText = true
            editor.allowsUndo = true
            editor.textContainerInset = NSSize(width: 10, height: 8)
            scroll.documentView = editor
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            return scroll
        }
        func updateNSView(_ scroll: NSScrollView, context: Context) {
            guard let editor = scroll.documentView as? NSTextView else { return }
            if editor.string != text { editor.string = text }
            if !search.isEmpty, let range = editor.string.range(of: search, options: .caseInsensitive) {
                let nsRange = NSRange(range, in: editor.string)
                editor.scrollRangeToVisible(nsRange)
                editor.setSelectedRange(nsRange)
            }
        }
        final class Coordinator: NSObject, NSTextViewDelegate {
            @Binding var text: String
            init(text: Binding<String>) { _text = text }
            func textDidChange(_ notification: Notification) {
                if let editor = notification.object as? NSTextView { text = editor.string }
            }
        }
    }

    private struct MarkdownNotesView: View {
        @Binding var text: String
        var search: String = ""
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.contains("- [ ] ") || line.contains("- [x] ") || line.contains("- [X] ") {
                            let checked = line.contains("- [x] ") || line.contains("- [X] ")
                            Button { toggleChecklist(line) } label: {
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    Text(line.replacingOccurrences(of: "- [x] ", with: "").replacingOccurrences(of: "- [X] ", with: "").replacingOccurrences(of: "- [ ] ", with: ""))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        } else if let rendered = try? AttributedString(markdown: line.isEmpty ? "  " : line) {
                            Text(rendered).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.system(size: 14, design: .rounded))
                .padding(12)
            }
        }
        private var lines: [String] {
            let all = text.isEmpty ? ["_Belum ada catatan_"] : text.components(separatedBy: "\n")
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return query.isEmpty ? all : all.filter { $0.lowercased().contains(query) }
        }
        private func toggleChecklist(_ line: String) {
            let replacement = (line.contains("- [x] ") || line.contains("- [X] ")) ? "- [ ] " : "- [x] "
            let body = line.components(separatedBy: "] ").dropFirst().joined(separator: "] ")
            text = text.components(separatedBy: "\n").map { $0 == line ? replacement + body : $0 }.joined(separator: "\n")
        }
    }

    private var boardLayout: some View {
        GeometryReader { boardProxy in
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 12) {
                        ForEach(TaskStatus.allCases) { status in
                            KanbanColumn(
                                status: status,
                                store: store,
                                projectFilter: selectedProjectRaw.isEmpty ? nil : selectedProjectRaw,
                                onAddTask: { taskEditorStatus = status; showingTaskEditor = true },
                                stacksCardActions: boardProxy.size.width < 900,
                                gestureTargeted: targetStatus(at: dragLocation, width: boardProxy.size.width) == status,
                                onTaskDragChanged: { task, location in
                                    draggedTask = task
                                    dragLocation = location
                                },
                                onTaskDragEnded: { task, location in
                                    if let destination = targetStatus(at: location, width: boardProxy.size.width) {
                                        store.move(task, to: destination)
                                    }
                                    draggedTask = nil
                                    dragLocation = nil
                                },
                                onTaskReorder: { task, moveUp in
                                    store.swapAdjacent(task, movingUp: moveUp)
                                }
                            )
                        }
                    }

                    if let task = draggedTask, let location = dragLocation {
                        HStack(spacing: 7) {
                            Image(systemName: "rectangle.stack.fill")
                            Text(task.title).lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.blue.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
                        .position(location)
                        .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "kanbanBoard")
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                footer
            }
        }
    }

    private func targetStatus(at location: CGPoint?, width: CGFloat) -> TaskStatus? {
        guard let location, width > 0, location.x >= 0, location.x <= width else { return nil }
        let index = min(2, max(0, Int((location.x / width) * 3)))
        return TaskStatus.allCases[index]
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Button(action: { NSApplication.shared.hide(nil) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.72), in: Circle())
                    .foregroundStyle(theme.background)
            }
            .buttonStyle(.plain)
            .help("Sembunyikan widget")

            Button(action: toggleFold) {
                Image(systemName: isFolded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.yellow.opacity(0.82), in: Circle())
                    .foregroundStyle(Color.black.opacity(0.62))
            }
            .buttonStyle(.plain)
            .help(isFolded ? "Buka widget" : "Lipat widget")

            ZStack {
                NativeWindowDragHandle()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 10) {
                    Text("Kanban Sticky")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .allowsHitTesting(false)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showNotes.toggle() }
                    } label: {
                        Image(systemName: showNotes ? "note.text" : "note")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(.white.opacity(showNotes ? 0.2 : 0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(showNotes ? "Sembunyikan notes" : "Tampilkan notes")
                    Button {
                        taskEditorStatus = selectedStatus
                        showingTaskEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Tambah task")
                    Menu {
                        Button("Semua project") { selectedProjectRaw = "" }
                        Button("Kelola project…") { showingProjectManager = true }
                        if !store.projects.isEmpty { Divider() }
                        ForEach(store.projects, id: \.self) { project in
                            Button(project) { selectedProjectRaw = project }
                        }
                    } label: {
                        Image(systemName: selectedProjectRaw.isEmpty ? "folder" : "folder.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(selectedProjectRaw.isEmpty ? "Filter project" : "Project: \(selectedProjectRaw)")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            .help("Tarik untuk memindahkan widget")

            Menu {
                ForEach(NoteTheme.allCases) { item in
                    Button {
                        themeRaw = item.rawValue
                    } label: {
                        Label(item.name, systemImage: item == theme ? "checkmark" : "circle.fill")
                    }
                }
                Divider()
                Toggle("Background transparan", isOn: $transparentBackground)
                Divider()
                Button("Keluar Kanban Sticky", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 25, height: 25)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusPicker: some View {
        HStack(spacing: 6) {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStatus = status
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: status.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(status.rawValue)
                            .lineLimit(1)
                        Text("\(store.count(for: status))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.white.opacity(status == selectedStatus ? 0.22 : 0.1), in: Capsule())
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(status == selectedStatus ? .white.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var taskList: some View {
        Group {
            if visibleTasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: selectedStatus == .done ? "sparkles" : "tray")
                        .font(.system(size: 28, weight: .light))
                    Text(selectedStatus == .done ? "Belum ada yang selesai" : "Kolom ini masih kosong")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visibleTasks) { task in
                            TaskRow(
                                task: task,
                                store: store,
                                onVerticalReorder: { moveUp in
                                    store.swapAdjacent(task, movingUp: moveUp)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var composer: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
            TextField("Tambah ke \(selectedStatus.rawValue)…", text: $newTask)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .focused($inputFocused)
                .onSubmit(addTask)
            Picker("Project", selection: $newTaskProject) {
                Text("Project").tag("")
                ForEach(store.projects, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 70)
            Button {
                showingNewTaskSchedule = true
            } label: {
                Image(systemName: newTaskHasStartDate || newTaskHasEndDate ? "calendar.badge.clock" : "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(newTaskHasStartDate || newTaskHasEndDate ? 0.2 : 0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Atur tanggal task")
            .popover(isPresented: $showingNewTaskSchedule, arrowEdge: .bottom) {
                DraftSchedulePicker(
                    hasStartDate: $newTaskHasStartDate,
                    hasEndDate: $newTaskHasEndDate,
                    startDate: $newTaskStartDate,
                    endDate: $newTaskEndDate
                )
            }
            Button(action: addTask) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(newTask.trimmingCharacters(in: .whitespaces).isEmpty ? 0.08 : 0.2), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(inputFocused ? 0.28 : 0.1), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            HStack {
                Text("\(store.count(for: .done)) dari \(store.tasks.count) selesai")
                Spacer()
                Text("\(Int(completion * 100))%")
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.16))
                    Capsule().fill(.white.opacity(0.72))
                        .frame(width: proxy.size.width * completion)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func addTask() {
        store.add(
            newTask,
            to: selectedStatus,
            project: newTaskProject,
            startDate: newTaskHasStartDate ? newTaskStartDate : nil,
            endDate: newTaskHasEndDate ? newTaskEndDate : nil
        )
        newTask = ""
        newTaskProject = ""
        newTaskHasStartDate = false
        newTaskHasEndDate = false
        inputFocused = true
    }

    private func toggleFold() {
        guard let window = NSApplication.shared.windows.first(where: {
            $0.title == "Kanban Sticky" && $0.isVisible
        }) else { return }

        let topEdge = window.frame.maxY
        if isFolded {
            let restoredHeight = max(430, expandedWindowHeight)
            window.minSize = NSSize(width: 360, height: 430)
            var frame = window.frame
            frame.size.height = restoredHeight
            frame.origin.y = topEdge - restoredHeight
            isFolded = false
            window.setFrame(frame, display: true, animate: true)
        } else {
            expandedWindowHeight = window.frame.height
            // The transparent native title bar still reserves vertical space.
            // Keep enough outer height so the compact 40pt header is not clipped.
            let foldedHeight: CGFloat = 76
            window.minSize = NSSize(width: 360, height: foldedHeight)
            var frame = window.frame
            frame.size.height = foldedHeight
            frame.origin.y = topEdge - foldedHeight
            isFolded = true
            window.setFrame(frame, display: true, animate: true)
        }
    }

}

private struct ProjectManagerView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var newProject = ""
    @State private var editingProject: String?
    @State private var editedName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kelola project").font(.headline)
                Spacer()
                Button("Selesai") { dismiss() }
            }
            HStack {
                TextField("Nama project baru", text: $newProject)
                    .textFieldStyle(.roundedBorder)
                Button("Tambah") { store.addProject(newProject); newProject = "" }
                    .disabled(newProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            List {
                ForEach(store.projects, id: \.self) { project in
                    HStack {
                        if editingProject == project {
                            TextField("Project", text: $editedName)
                                .onSubmit { commitEdit(project) }
                            Button("Simpan") { commitEdit(project) }
                        } else {
                            Label(project, systemImage: "folder")
                            Spacer()
                            Button("Edit") { editingProject = project; editedName = project }
                            Button("Hapus", role: .destructive) { store.deleteProject(project) }
                        }
                    }
                }
            }
            .frame(minHeight: 140)
        }
        .padding(20)
        .frame(width: 420, height: 320)
    }

    private func commitEdit(_ old: String) {
        store.renameProject(old, to: editedName)
        editingProject = nil
        editedName = ""
    }

}

private struct TaskEditorView: View {
    @ObservedObject var store: TaskStore
    let task: KanbanTask?
    let initialStatus: TaskStatus
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var project = ""
    @State private var status: TaskStatus
    @State private var startDate: Date?
    @State private var endDate: Date?

    init(store: TaskStore, task: KanbanTask? = nil, initialStatus: TaskStatus = .todo) {
        self.store = store; self.task = task; self.initialStatus = initialStatus
        _status = State(initialValue: task?.status ?? initialStatus)
        _title = State(initialValue: task?.title ?? "")
        _project = State(initialValue: task?.project ?? "")
        _startDate = State(initialValue: task?.startDate)
        _endDate = State(initialValue: task?.endDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task == nil ? "Tambah task" : "Edit task").font(.headline)
            TextField("Judul task", text: $title).textFieldStyle(.roundedBorder)
            Picker("Project", selection: $project) {
                Text("Tanpa project").tag("")
                ForEach(store.projects, id: \.self) { Text($0).tag($0) }
            }
            Picker("Status", selection: $status) { ForEach(TaskStatus.allCases) { Text($0.rawValue).tag($0) } }
            HStack { DatePicker("Mulai", selection: Binding(get: { startDate ?? Date() }, set: { startDate = $0 }), displayedComponents: .date); Toggle("Aktif", isOn: Binding(get: { startDate != nil }, set: { if !$0 { startDate = nil } else if startDate == nil { startDate = Date() } })) }
            HStack { DatePicker("Selesai", selection: Binding(get: { endDate ?? Date() }, set: { endDate = $0 }), displayedComponents: .date); Toggle("Aktif", isOn: Binding(get: { endDate != nil }, set: { if !$0 { endDate = nil } else if endDate == nil { endDate = Date() } })) }
            HStack { Spacer(); Button("Batal") { dismiss() }; Button("Simpan") { save() }.keyboardShortcut(.return) }
        }.padding(20).frame(width: 430)
    }
    private func save() { guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; if let task { store.rename(task, to: title); store.move(task, to: status); store.setProject(for: task, project: project); store.setSchedule(for: task, startDate: startDate, endDate: endDate) } else { store.add(title, to: status, project: project, startDate: startDate, endDate: endDate) }; dismiss() }
}

private struct TaskRow: View {
    let task: KanbanTask
    @ObservedObject var store: TaskStore
    var onDragChanged: ((CGPoint) -> Void)? = nil
    var onDragEnded: ((CGPoint) -> Void)? = nil
    var onVerticalReorder: ((Bool) -> Void)? = nil
    var stackActionsBelow: Bool = false
    @State private var hovering = false
    @State private var showingSchedule = false
    @State private var isEditing = false
    @State private var showingTaskEditor = false
    @State private var isVerticalDragging = false
    @State private var lastSwapTranslation: CGFloat = 0
    @State private var verticalDragDirection: Int = 0
    @State private var editedTitle = ""
    @State private var rowWidth: CGFloat = 400
    @FocusState private var titleFieldFocused: Bool

    private var usesStackedActions: Bool { stackActionsBelow || rowWidth < 285 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                store.move(task, to: task.status == .done ? .todo : .done)
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(task.status == .done ? .white : .white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help(task.status == .done ? "Kembalikan ke Todo" : "Tandai selesai")

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Judul task", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .focused($titleFieldFocused)
                        .onSubmit(saveTitle)
                        .onExitCommand(perform: cancelEditing)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(task.title)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .strikethrough(task.status == .done, color: .white.opacity(0.55))
                        .foregroundStyle(.white.opacity(task.status == .done ? 0.62 : 0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2, perform: beginEditing)
                        .help("Double-click untuk edit")
                }

                if let project = task.project, !project.isEmpty {
                    Label(project, systemImage: "folder.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                if task.startDate != nil || task.endDate != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(scheduleText)
                    }
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                }

                if hovering && !isEditing && usesStackedActions {
                    actionButtons
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("kanbanBoard"))
                    .onChanged { value in
                        onDragChanged?(value.location)
                    }
                    .onEnded { value in
                        onDragEnded?(value.location)
                    },
                including: isEditing ? .none : .all
            )

            if hovering && !isEditing && !usesStackedActions {
                actionButtons
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.white.opacity(isVerticalDragging ? 0.24 : (hovering ? 0.15 : 0.1)), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .scaleEffect(isVerticalDragging ? 1.03 : 1, anchor: .leading)
        .zIndex(isVerticalDragging ? 10 : 0)
        .overlay(alignment: .leading) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isVerticalDragging ? .white : statusColor)
                    .frame(width: 3)
                    .padding(.vertical, 7)
                    .padding(.leading, 1)
                Rectangle()
                    .fill(.white.opacity(0.001))
                    .frame(width: 18)
                    .contentShape(Rectangle())
                    .help("Tahan garis untuk mengatur urutan vertikal")
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            guard abs(value.translation.height) > abs(value.translation.width),
                                  abs(value.translation.height) > 6 else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                isVerticalDragging = true
                            }
                            let distanceSinceSwap = value.translation.height - lastSwapTranslation
                            let direction = distanceSinceSwap < 0 ? -1 : 1
                            if verticalDragDirection == 0 {
                                verticalDragDirection = direction
                            }
                            if direction == verticalDragDirection && abs(distanceSinceSwap) > 38 {
                                onVerticalReorder?(verticalDragDirection < 0)
                                lastSwapTranslation = value.translation.height
                            }
                        }
                        .onEnded { value in
                            guard abs(value.translation.height) > abs(value.translation.width),
                                  abs(value.translation.height) > 10 else {
                                isVerticalDragging = false
                                lastSwapTranslation = 0
                                verticalDragDirection = 0
                                return
                            }
                            withAnimation(.easeOut(duration: 0.16)) {
                                isVerticalDragging = false
                            }
                            lastSwapTranslation = 0
                            verticalDragDirection = 0
                        },
                        including: isEditing ? .none : .all
                    )
            }
            .frame(maxHeight: .infinity, alignment: .leading)
        }
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.14)) { hovering = isHovering }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: TaskRowWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(TaskRowWidthPreferenceKey.self) { width in
            rowWidth = width
        }
        .popover(isPresented: $showingSchedule, arrowEdge: .trailing) {
            TaskScheduleEditor(task: task, store: store)
        }
        .sheet(isPresented: $showingTaskEditor) {
            TaskEditorView(store: store, task: task)
        }
        .contextMenu {
            Button("Edit judul") { beginEditing() }
            Button("Atur tanggal…") { showingSchedule = true }
            if task.startDate != nil || task.endDate != nil {
                Button("Hapus jadwal") {
                    store.setSchedule(for: task, startDate: nil, endDate: nil)
                }
            }
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo: return .white.opacity(0.42)
        case .progress: return .yellow.opacity(0.85)
        case .done: return .mint.opacity(0.9)
        }
    }

    private func beginEditing() {
        showingTaskEditor = true
    }

    private func saveTitle() {
        let cleanTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            cancelEditing()
            return
        }
        store.rename(task, to: cleanTitle)
        isEditing = false
        titleFieldFocused = false
    }

    private func cancelEditing() {
        editedTitle = task.title
        isEditing = false
        titleFieldFocused = false
    }

    private var scheduleText: String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        switch (task.startDate, task.endDate) {
        case let (start?, end?):
            return "\(start.formatted(format)) – \(end.formatted(format))"
        case let (start?, nil):
            return "Mulai \(start.formatted(format))"
        case let (nil, end?):
            return "Selesai \(end.formatted(format))"
        case (nil, nil):
            return ""
        }
    }

    private func actionButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.13), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            actionButton("pencil") { beginEditing() }
            actionButton(task.startDate != nil || task.endDate != nil ? "calendar.badge.clock" : "calendar") {
                showingSchedule = true
            }
            if task.status != .todo {
                actionButton("chevron.left") {
                    store.move(task, to: task.status == .done ? .progress : .todo)
                }
            }
            if task.status != .done {
                actionButton("chevron.right") {
                    store.move(task, to: task.status == .todo ? .progress : .done)
                }
            }
            actionButton("trash") { store.remove(task) }
        }
    }
}

private struct TaskRowWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TaskScheduleEditor: View {
    let task: KanbanTask
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var hasStartDate: Bool
    @State private var hasEndDate: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(task: KanbanTask, store: TaskStore) {
        self.task = task
        self.store = store
        _hasStartDate = State(initialValue: task.startDate != nil)
        _hasEndDate = State(initialValue: task.endDate != nil)
        _startDate = State(initialValue: task.startDate ?? Date())
        _endDate = State(initialValue: task.endDate ?? task.startDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jadwal Task")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(task.title)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            scheduleRow(title: "Tanggal mulai", isEnabled: $hasStartDate, date: $startDate)
            scheduleRow(title: "Tanggal selesai", isEnabled: $hasEndDate, date: $endDate)

            HStack {
                if task.startDate != nil || task.endDate != nil {
                    Button("Hapus") {
                        store.setSchedule(for: task, startDate: nil, endDate: nil)
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Batal") { dismiss() }
                Button("Simpan") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func scheduleRow(
        title: String,
        isEnabled: Binding<Bool>,
        date: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(title, isOn: isEnabled)
                .font(.system(size: 12, weight: .medium, design: .rounded))
            if isEnabled.wrappedValue {
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
        }
    }

    private func save() {
        let start = hasStartDate ? startDate : nil
        var end = hasEndDate ? endDate : nil
        if let start, let currentEnd = end, currentEnd < start {
            end = start
        }
        store.setSchedule(for: task, startDate: start, endDate: end)
        dismiss()
    }
}

private struct KanbanColumn: View {
    let status: TaskStatus
    @ObservedObject var store: TaskStore
    let projectFilter: String?
    let onAddTask: () -> Void
    let stacksCardActions: Bool
    let gestureTargeted: Bool
    let onTaskDragChanged: (KanbanTask, CGPoint) -> Void
    let onTaskDragEnded: (KanbanTask, CGPoint) -> Void
    let onTaskReorder: (KanbanTask, Bool) -> Void
    @State private var draft = ""
    @State private var draftProject = ""
    @State private var draftHasStartDate = false
    @State private var draftHasEndDate = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()
    @State private var showingDraftSchedule = false
    @State private var nativeTargeted = false

    private var tasks: [KanbanTask] {
        store.tasks.filter { $0.status == status && (projectFilter == nil || $0.project == projectFilter) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: status.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(status.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule())
                Button(action: onAddTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Tambah task ke \(status.rawValue)")
            }
            .padding(.horizontal, 3)

            Group {
                if tasks.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "tray")
                            .font(.system(size: 23, weight: .light))
                        Text("Tarik task ke sini")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.46))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(tasks) { task in
                                TaskRow(
                                    task: task,
                                    store: store,
                                    onDragChanged: { onTaskDragChanged(task, $0) },
                                    onDragEnded: { onTaskDragEnded(task, $0) },
                                    onVerticalReorder: { onTaskReorder(task, $0) },
                                    stackActionsBelow: stacksCardActions
                                )
                            }
                        }
                        .padding(4)
                    }
                    .scrollIndicators(.visible)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .padding(10)
        .background(
            gestureTargeted || nativeTargeted ? .white.opacity(0.17) : .black.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    .white.opacity(gestureTargeted || nativeTargeted ? 0.5 : 0.08),
                    lineWidth: gestureTargeted || nativeTargeted ? 2 : 1
                )
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let identifier = identifiers.first,
                  let id = UUID(uuidString: identifier),
                  let task = store.tasks.first(where: { $0.id == id }) else {
                return false
            }
            store.move(task, to: status)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) {
                nativeTargeted = targeted
            }
        }
    }

    private func addTask() {
        store.add(
            draft,
            to: status,
            project: draftProject,
            startDate: draftHasStartDate ? draftStartDate : nil,
            endDate: draftHasEndDate ? draftEndDate : nil
        )
        draft = ""
        draftProject = ""
        draftHasStartDate = false
        draftHasEndDate = false
    }
}

private struct DraftSchedulePicker: View {
    @Binding var hasStartDate: Bool
    @Binding var hasEndDate: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tanggal Task Baru")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            dateRow(title: "Tanggal mulai", isEnabled: $hasStartDate, date: $startDate)
            dateRow(title: "Tanggal selesai", isEnabled: $hasEndDate, date: $endDate)

            HStack {
                if hasStartDate || hasEndDate {
                    Button("Reset") {
                        hasStartDate = false
                        hasEndDate = false
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Terapkan") {
                    if hasStartDate && hasEndDate && endDate < startDate {
                        endDate = startDate
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 285)
    }

    private func dateRow(
        title: String,
        isEnabled: Binding<Bool>,
        date: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(title, isOn: isEnabled)
                .font(.system(size: 12, weight: .medium, design: .rounded))
            if isEnabled.wrappedValue {
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
        }
    }
}

private final class NativeWindowDragNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

private struct NativeWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NativeWindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let store = TaskStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        let content = ContentView(store: store)
        let hostingView = NSHostingView(rootView: content)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Kanban Sticky"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Only HeaderDragView moves the window. Enabling background movement here
        // steals drag gestures from kanban cards.
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 360, height: 430)
        window.maxSize = NSSize(width: 1320, height: 900)
        if !window.setFrameUsingName("KanbanStickyWindow") {
            window.center()
        }
        window.setFrameAutosaveName("KanbanStickyWindow")
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        configureMenuBar()
        installLaunchAgent()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command), event.keyCode == 13 {
                self?.window.orderOut(nil)
                return nil
            }
            return event
        }
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Kanban Sticky")
        appMenu.addItem(menuItem("Keluar Kanban Sticky", action: #selector(quitApp), key: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(responderMenuItem("Undo", action: Selector(("undo:")), key: "z"))
        let redo = responderMenuItem("Redo", action: Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(responderMenuItem("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(responderMenuItem("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(responderMenuItem("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(responderMenuItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func responderMenuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        return item
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Kanban Sticky")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Kanban Sticky"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleTitle = window.isVisible
            ? "Sembunyikan Widget"
            : "Tampilkan Widget"
        menu.addItem(menuItem(toggleTitle, action: #selector(toggleWidget), key: "k"))

        let addItem = NSMenuItem(title: "Task Baru", action: nil, keyEquivalent: "")
        let addMenu = NSMenu()
        addMenu.addItem(menuItem("Ke Todo", action: #selector(newTodo)))
        addMenu.addItem(menuItem("Ke Progress", action: #selector(newProgress)))
        addMenu.addItem(menuItem("Ke Done", action: #selector(newDone)))
        addItem.submenu = addMenu
        menu.addItem(addItem)

        menu.addItem(.separator())
        for status in TaskStatus.allCases {
            let item = NSMenuItem(
                title: "\(status.rawValue)   \(store.count(for: status))",
                action: nil,
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: status.icon, accessibilityDescription: status.rawValue)
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Jalankan saat Login", action: nil, keyEquivalent: "")
        loginItem.state = launchAgentExists ? .on : .off
        loginItem.isEnabled = false
        menu.addItem(loginItem)
        menu.addItem(menuItem("Keluar Kanban Sticky", action: #selector(quitApp), key: "q"))
    }

    private var launchAgentURL: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.assistance.kanbansticky.plist")
    }

    private var launchAgentExists: Bool {
        guard let url = launchAgentURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func installLaunchAgent() {
        guard let url = launchAgentURL else { return }
        let directory = url.deletingLastPathComponent()
        let configuration: [String: Any] = [
            "Label": "com.assistance.kanbansticky",
            "ProgramArguments": ["/usr/bin/open", "-b", "com.assistance.kanbansticky"],
            "RunAtLoad": true,
            "ProcessType": "Background"
        ]

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: configuration,
                format: .xml,
                options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Kanban Sticky gagal mengaktifkan run on login: \(error.localizedDescription)")
        }
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleWidget() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWidget()
        }
    }

    @objc private func newTodo() { showComposer(for: .todo) }
    @objc private func newProgress() { showComposer(for: .progress) }
    @objc private func newDone() { showComposer(for: .done) }

    private func showComposer(for status: TaskStatus) {
        UserDefaults.standard.set(status.rawValue, forKey: "kanbanSticky.selectedStatus")
        showWidget()
    }

    private func showWidget() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

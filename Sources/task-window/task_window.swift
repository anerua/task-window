import Foundation

public struct TaskItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var isCompleted: Bool
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

public struct TaskList: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var tasks: [TaskItem]
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, tasks: [TaskItem] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tasks = tasks
        self.createdAt = createdAt
    }

    public var sortedTasks: [TaskItem] {
        TaskOrdering.sort(tasks)
    }
}

public enum TaskOrdering {
    public static func sort(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

#if os(macOS)
import AppKit
import Combine
import ServiceManagement
import SwiftUI

private struct PersistedState: Codable {
    var lists: [TaskList]
    var selectedListID: UUID?
}

@MainActor
final class TaskAppModel: ObservableObject {
    @Published private(set) var lists: [TaskList] = []
    @Published var selectedListID: UUID?
    @Published private(set) var launchAtLoginEnabled: Bool

    var selectedList: TaskList? {
        guard let selectedListID else { return nil }
        return lists.first(where: { $0.id == selectedListID })
    }

    private let stateURL: URL?
    private let defaults = UserDefaults.standard
    private let launchAtLoginKey = "launchAtLoginEnabled"
    private let launchAgentLabel: String

    init() {
        self.stateURL = Self.makeStateURL()
        self.launchAgentLabel = (Bundle.main.bundleIdentifier ?? "com.anerua.task-window") + ".login"
        if defaults.object(forKey: launchAtLoginKey) == nil {
            launchAtLoginEnabled = true
            defaults.set(true, forKey: launchAtLoginKey)
        } else {
            launchAtLoginEnabled = defaults.bool(forKey: launchAtLoginKey)
        }
        loadState()
        applyLaunchAtLogin()
    }

    func setLaunchAtLogin(enabled: Bool) {
        launchAtLoginEnabled = enabled
        defaults.set(enabled, forKey: launchAtLoginKey)
        applyLaunchAtLogin()
    }

    func createList(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let list = TaskList(name: trimmed)
        lists.append(list)
        if selectedListID == nil {
            selectedListID = list.id
        }
        saveState()
    }

    func renameList(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = lists.firstIndex(where: { $0.id == id }) else {
            return
        }
        lists[index].name = trimmed
        saveState()
    }

    func deleteList(id: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists.remove(at: index)
        if selectedListID == id {
            selectedListID = lists.first?.id
        }
        saveState()
    }

    func selectList(id: UUID) {
        guard lists.contains(where: { $0.id == id }) else { return }
        selectedListID = id
        saveState()
    }

    func addTask(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let listIndex = selectedListIndex else {
            return
        }

        lists[listIndex].tasks.append(TaskItem(text: trimmed))
        saveState()
    }

    func updateTask(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let (listIndex, taskIndex) = taskIndex(id: id) else {
            return
        }

        lists[listIndex].tasks[taskIndex].text = trimmed
        saveState()
    }

    func toggleTask(id: UUID) {
        guard let (listIndex, taskIndex) = taskIndex(id: id) else { return }
        lists[listIndex].tasks[taskIndex].isCompleted.toggle()
        saveState()
    }

    func deleteTask(id: UUID) {
        guard let (listIndex, taskIndex) = taskIndex(id: id) else { return }
        lists[listIndex].tasks.remove(at: taskIndex)
        saveState()
    }

    private var selectedListIndex: Int? {
        guard let selectedListID else { return nil }
        return lists.firstIndex(where: { $0.id == selectedListID })
    }

    private func taskIndex(id: UUID) -> (Int, Int)? {
        guard let listIndex = selectedListIndex,
              let taskIndex = lists[listIndex].tasks.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return (listIndex, taskIndex)
    }

    private static func makeStateURL() -> URL? {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDir = supportDir.appendingPathComponent("task-window", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("state.json")
    }

    private func loadState() {
        guard let stateURL,
              let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }

        lists = state.lists
        if let selectedID = state.selectedListID,
           lists.contains(where: { $0.id == selectedID }) {
            selectedListID = selectedID
        } else {
            selectedListID = lists.first?.id
        }
    }

    private func saveState() {
        guard let stateURL else { return }
        let state = PersistedState(lists: lists, selectedListID: selectedListID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            syncLaunchAtLoginStateFromSystem()
        } catch {
            // Fallback for local/dev builds where SMAppService registration can fail.
            applyLaunchAgentFallback(enabled: launchAtLoginEnabled)
            syncLaunchAtLoginStateFromSystem()
        }
    }

    private func syncLaunchAtLoginStateFromSystem() {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                launchAtLoginEnabled = true
                return
            case .notFound:
                break
            case .notRegistered:
                break
            case .requiresApproval:
                launchAtLoginEnabled = true
                return
            @unknown default:
                break
            }
        }
        launchAtLoginEnabled = launchAgentIsInstalled()
    }

    private func launchAgentIsInstalled() -> Bool {
        guard let launchAgentURL else { return false }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private var launchAgentURL: URL? {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let agentsDir = libraryURL.appendingPathComponent("LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        return agentsDir.appendingPathComponent("\(launchAgentLabel).plist")
    }

    private func applyLaunchAgentFallback(enabled: Bool) {
        guard let launchAgentURL else { return }

        if enabled {
            guard let plistData = launchAgentPlistData() else { return }
            do {
                try plistData.write(to: launchAgentURL, options: .atomic)
                runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", launchAgentURL.path])
            } catch {
                return
            }
        } else {
            runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentURL.path])
            try? FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private func launchAgentPlistData() -> Data? {
        guard let executablePath = Bundle.main.executableURL?.path else {
            return nil
        }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        return try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private func runLaunchctl(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}

@MainActor
final class TaskWindowController {
    private var controller: NSWindowController?
    private var closeDelegate: NSWindowDelegate?

    func show<Content: View>(
        title: String,
        size: NSSize,
        @ViewBuilder content: () -> Content
    ) {
        if let existing = controller {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: AnyView(content()))
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()

        let newController = NSWindowController(window: window)
        let closeDelegate = WindowCloseDelegate { [weak self] in
            self?.controller = nil
            self?.closeDelegate = nil
        }
        newController.window?.delegate = closeDelegate
        self.closeDelegate = closeDelegate
        controller = newController

        newController.showWindow(nil)
        newController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func windowWillClose(_ notification: Notification) {
            onClose()
        }
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let model = TaskAppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let settingsWindow = TaskWindowController()
    private let aboutWindow = TaskWindowController()
    private let listPromptWindow = TaskWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Task Window")
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.contentViewController = NSHostingController(rootView: AnyView(
            MainPanelView(
                model: model,
                onCreateList: { [weak self] in
                    self?.showListPromptForCreate()
                },
                onEditList: { [weak self] list in
                    self?.showListPromptForEdit(list)
                }
            )
        ))
    }

    @objc
    private func statusItemClicked() {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()

            menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc
    private func showSettings() {
        settingsWindow.show(title: "Settings", size: NSSize(width: 320, height: 120)) {
            SettingsView(model: model)
                .padding(16)
        }
    }

    @objc
    private func showAbout() {
        aboutWindow.show(title: "About", size: NSSize(width: 360, height: 150)) {
            AboutView()
                .padding(16)
        }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showListPromptForCreate() {
        showListPrompt(title: "New Task List", initialName: "") { [weak self] name in
            self?.model.createList(named: name)
        }
    }

    private func showListPromptForEdit(_ list: TaskList) {
        showListPrompt(title: "Edit Task List", initialName: list.name) { [weak self] name in
            self?.model.renameList(id: list.id, newName: name)
        }
    }

    private func showListPrompt(title: String, initialName: String, onSubmit: @escaping (String) -> Void) {
        listPromptWindow.show(title: title, size: NSSize(width: 320, height: 120)) {
            TaskListPromptView(
                initialName: initialName,
                onSubmit: onSubmit
            )
            .padding(16)
        }
    }
}

private struct MainPanelView: View {
    @ObservedObject var model: TaskAppModel
    var onCreateList: () -> Void
    var onEditList: (TaskList) -> Void

    @State private var newTaskText = ""

    var body: some View {
        VStack(spacing: 12) {
            HeaderView(model: model, onCreateList: onCreateList, onEditList: onEditList)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    if let selectedList = model.selectedList {
                        ForEach(selectedList.sortedTasks) { task in
                            TaskRowView(
                                task: task,
                                onToggle: { model.toggleTask(id: task.id) },
                                onDelete: { model.deleteTask(id: task.id) },
                                onUpdate: { model.updateTask(id: task.id, text: $0) }
                            )
                        }
                    } else {
                        Text("Create a task list to get started")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Add a task", text: $newTaskText, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)

                Button("Add", action: addTask)
                    .disabled(newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.selectedList == nil)
            }
        }
        .padding(12)
        .frame(width: 380, height: 500)
    }

    private func addTask() {
        let value = newTaskText
        model.addTask(text: value)
        newTaskText = ""
    }
}

private struct HeaderView: View {
    @ObservedObject var model: TaskAppModel
    var onCreateList: () -> Void
    var onEditList: (TaskList) -> Void

    @State private var showListDropdown = false

    var body: some View {
        HStack {
            Button(action: { showListDropdown.toggle() }) {
                HStack {
                    Text(model.selectedList?.name ?? "Select task list")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showListDropdown, arrowEdge: .top) {
                TaskListDropdownView(
                    model: model,
                    onEditList: onEditList
                )
                .frame(width: 280)
                .padding(8)
            }

            Spacer()

            Button(action: onCreateList) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help("Create Task List")
        }
    }
}

private struct TaskListDropdownView: View {
    @ObservedObject var model: TaskAppModel
    var onEditList: (TaskList) -> Void

    @State private var listToDelete: TaskList?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.lists) { list in
                HStack(spacing: 8) {
                    Button(action: { model.selectList(id: list.id) }) {
                        Text(list.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onEditList(list) }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: { listToDelete = list }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            if model.lists.isEmpty {
                Text("No task lists")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog(
            "Delete task list?",
            isPresented: Binding(
                get: { listToDelete != nil },
                set: { if !$0 { listToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let listToDelete {
                    model.deleteList(id: listToDelete.id)
                    self.listToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                listToDelete = nil
            }
        } message: {
            Text("Deleting this list will remove all tasks in it.")
        }
    }
}

private struct TaskRowView: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onUpdate: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.square" : "square")
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("Task", text: $editText, axis: .vertical)
                    .lineLimit(1...4)
                    .onSubmit(commitEdit)
                    .onAppear {
                        editText = task.text
                    }
            } else {
                Text(task.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .onTapGesture {
                        editText = task.text
                        isEditing = true
                    }
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func commitEdit() {
        onUpdate(editText)
        isEditing = false
    }
}

private struct SettingsView: View {
    @ObservedObject var model: TaskAppModel

    var body: some View {
        // Still a little buggy
        Toggle(
            "Start at login",
            isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin(enabled: $0) }
            )
        )
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Window")
                .font(.headline)
            Text("A simple menu bar todo app for macOS.")
            Text("Author: @anerua, @copilot")
                .foregroundStyle(.secondary)
            Text("Copyright © 2026 Martins Anerua. All rights reserved.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TaskListPromptView: View {
    @State private var name: String
    let onSubmit: (String) -> Void

    init(initialName: String, onSubmit: @escaping (String) -> Void) {
        _name = State(initialValue: initialName)
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Task list name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Save", action: submit)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func submit() {
        onSubmit(name)
        NSApp.keyWindow?.close()
    }
}
#endif

enum AppRuntime {
#if os(macOS)
    nonisolated(unsafe) static var coordinator: AppCoordinator?
#endif
}

@main
struct task_window {
    static func main() {
#if os(macOS)
        let app = NSApplication.shared
        let coordinator = AppCoordinator()
        AppRuntime.coordinator = coordinator
        app.setActivationPolicy(.accessory)
        app.delegate = coordinator
        app.run()
#else
        print("task-window is a macOS menu bar app.")
#endif
    }
}

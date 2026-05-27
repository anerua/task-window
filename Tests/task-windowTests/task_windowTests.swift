import Foundation
import Testing
@testable import task_window

@Test("Pending tasks appear before completed, each grouped by creation time")
func taskOrderingGroupsByCompletionThenDate() {
    let baseDate = Date(timeIntervalSince1970: 1_000)
    let tasks = [
        TaskItem(text: "Completed old", isCompleted: true, createdAt: baseDate),
        TaskItem(text: "Pending newest", isCompleted: false, createdAt: baseDate.addingTimeInterval(30)),
        TaskItem(text: "Pending oldest", isCompleted: false, createdAt: baseDate.addingTimeInterval(10)),
        TaskItem(text: "Completed newest", isCompleted: true, createdAt: baseDate.addingTimeInterval(40)),
    ]

    let ordered = TaskOrdering.sort(tasks)

    #expect(ordered.map(\ .text) == [
        "Pending oldest",
        "Pending newest",
        "Completed old",
        "Completed newest",
    ])
}

@Test("TaskList.sortedTasks uses the same ordering rules")
func taskListSortedTasksUsesOrderingRules() {
    let date = Date(timeIntervalSince1970: 5_000)
    let list = TaskList(
        name: "Work",
        tasks: [
            TaskItem(text: "done", isCompleted: true, createdAt: date),
            TaskItem(text: "todo", isCompleted: false, createdAt: date.addingTimeInterval(1)),
        ]
    )

    #expect(list.sortedTasks.map(\ .text) == ["todo", "done"])
}

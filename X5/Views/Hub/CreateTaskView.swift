import SwiftUI

struct CreateTaskView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void = {}

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var budget: String = ""
    @State private var category: String = "marketing"
    @State private var deadline: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var hasDeadline: Bool = false
    @State private var saving: Bool = false
    @State private var errorMessage: String?

    @StateObject private var hub = HubService()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Task")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(3...8)
                }
                Section(header: Text("Budget & category")) {
                    TextField("Budget (e.g. 50 000 ₸)", text: $budget)
                    Picker("Category", selection: $category) {
                        ForEach(HubCategories.all) { cat in
                            Text("\(cat.emoji)  \(cat.labelEn)").tag(cat.id)
                        }
                    }
                    Toggle("Set deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    }
                }
                if let err = errorMessage {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Post a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if saving { ProgressView() } else { Text("Post").bold() }
                    }
                    .disabled(saving || !canSubmit)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !budget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        saving = true
        defer { saving = false }
        let inserted = await hub.createTask(
            authorId: uid,
            authorName: currentUser.profile?.name ?? auth.userEmail,
            authorAvatar: currentUser.profile?.avatar,
            companyName: nil,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            budget: budget.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            deadline: hasDeadline ? deadline : nil,
            accessToken: token
        )
        if inserted != nil {
            onCreated()
            dismiss()
        } else {
            errorMessage = "Could not post the task. Please try again."
        }
    }
}

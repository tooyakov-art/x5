import SwiftUI

/// Specialist responds to a task. On success: insert task_response, ensure chat, navigate to chat.
struct RespondTaskView: View {
    let task: HubTask

    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @Environment(\.dismiss) private var dismiss

    @State private var message: String = ""
    @State private var saving: Bool = false
    @State private var errorMessage: String?
    @State private var navigatingChat: ChatRoom?

    @StateObject private var hub = HubService()
    @StateObject private var chats = ChatsService()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Task")) {
                    Text(task.title).font(.headline)
                    if let budget = task.budget, !budget.isEmpty {
                        HStack {
                            Text("Budget"); Spacer()
                            Text(budget).foregroundColor(.accentColor).bold()
                        }
                    }
                }
                Section(header: Text("Your message")) {
                    TextField("How can you help with this?", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let err = errorMessage {
                    Section { Text(err).foregroundColor(.red) }
                }
                Section(footer: Text("After the author accepts your response, a private chat will open automatically.")) {
                    EmptyView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.10))
            .navigationTitle("Respond")
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
                        if saving { ProgressView() } else { Text("Send").bold() }
                    }
                    .disabled(saving || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $navigatingChat) { chat in
            NavigationStack { ChatThreadView(chat: chat) }
                .preferredColorScheme(.dark)
        }
    }

    private func submit() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        saving = true
        defer { saving = false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let resp = await hub.respondToTask(
            taskId: task.id,
            specialistId: uid,
            specialistName: currentUser.profile?.name ?? auth.userEmail,
            specialistAvatar: currentUser.profile?.avatar,
            message: trimmed,
            accessToken: token
        )
        if resp == nil {
            errorMessage = "Could not send your response."
            return
        }
        // Open a chat with the task author tagged with this task
        if let chat = await chats.ensureChat(otherUserId: task.authorId, currentUserId: uid, taskId: task.id, taskTitle: task.title, accessToken: token) {
            // Send the response message into the chat as well so the author sees it
            _ = await chats.sendText(chatId: chat.id, currentUserId: uid, text: trimmed, accessToken: token)
            navigatingChat = chat
        } else {
            dismiss()
        }
    }
}

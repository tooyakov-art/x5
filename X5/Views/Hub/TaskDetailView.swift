import SwiftUI

struct TaskDetailView: View {
    let task: HubTask

    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @StateObject private var service = HubService()
    @StateObject private var chats = ChatsService()
    @State private var responses: [TaskResponse] = []
    @State private var showingRespond = false
    @State private var navigatingChat: ChatRoom?
    @State private var accepting: String?

    private var isAuthor: Bool { auth.userId == task.authorId }
    private var hasRespondedAlready: Bool {
        guard let me = auth.userId else { return false }
        return responses.contains { $0.specialistId == me }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(HubCategories.label(for: task.category).uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundColor(.accentColor)
                    Spacer()
                    if let budget = task.budget, !budget.isEmpty {
                        Text(budget)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }

                Text(task.title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white)

                if let desc = task.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().background(Color.white.opacity(0.06))

                HStack(spacing: 10) {
                    AvatarView(urlString: task.authorAvatar, name: task.authorName, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.authorName ?? "Anonymous")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        if let company = task.companyName, !company.isEmpty {
                            Text(company).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    if let deadline = task.deadline, !deadline.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Deadline").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundColor(.white.opacity(0.45))
                            Text(formatDate(deadline)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                }

                Text("RESPONSES (\(responses.count))")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 8)

                if responses.isEmpty {
                    Text("No responses yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(responses) { r in responseRow(r) }
                }

                if isAuthor {
                    Text("This is your task — you'll see responses above and can accept one.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 8)
                } else if hasRespondedAlready {
                    Text("Your response is sent. Wait for the author to accept it.")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor.opacity(0.85))
                        .padding(.top, 8)
                } else if task.status == "open" {
                    Button {
                        showingRespond = true
                    } label: {
                        Text("Respond to task")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                } else {
                    Text("This task is closed for new responses.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { responses = await service.loadResponses(taskId: task.id) }
        .sheet(isPresented: $showingRespond) {
            RespondTaskView(task: task)
        }
        .sheet(item: $navigatingChat) { chat in
            NavigationStack { ChatThreadView(chat: chat) }
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func responseRow(_ r: TaskResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(urlString: r.specialistAvatar, name: r.specialistName, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(r.specialistName ?? "Specialist")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        if r.status == "accepted" {
                            Text("ACCEPTED")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                        }
                    }
                    Text(r.message ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if isAuthor && r.status == "open" && task.status == "open" {
                Button {
                    Task { await accept(r) }
                } label: {
                    HStack {
                        if accepting == r.id { ProgressView().tint(.black) }
                        Text(accepting == r.id ? "Accepting…" : "Accept & open chat")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(accepting != nil)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func accept(_ r: TaskResponse) async {
        guard let token = auth.accessToken, let me = auth.userId else { return }
        accepting = r.id
        defer { accepting = nil }
        await service.acceptResponse(
            taskId: task.id,
            responseId: r.id,
            specialistId: r.specialistId,
            specialistName: r.specialistName,
            accessToken: token
        )
        if let chat = await chats.ensureChat(
            otherUserId: r.specialistId,
            currentUserId: me,
            taskId: task.id,
            taskTitle: task.title,
            accessToken: token
        ) {
            _ = await chats.sendText(
                chatId: chat.id,
                currentUserId: me,
                text: "I accepted your response on '\(task.title)'. Let's start.",
                accessToken: token
            )
            navigatingChat = chat
        }
        responses = await service.loadResponses(taskId: task.id)
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .short
        return out.string(from: d)
    }
}

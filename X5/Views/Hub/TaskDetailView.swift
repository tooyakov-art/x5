import SwiftUI

struct TaskDetailView: View {
    let task: HubTask

    @StateObject private var service = HubService()
    @State private var responses: [TaskResponse] = []

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
                            Text(company)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
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
                    ForEach(responses) { r in
                        HStack(alignment: .top, spacing: 10) {
                            AvatarView(urlString: r.specialistAvatar, name: r.specialistName, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.specialistName ?? "Specialist")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(r.message ?? "")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Button {} label: {
                    Text("Respond — coming soon")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor.opacity(0.55))
                        .cornerRadius(14)
                }
                .disabled(true)
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            responses = await service.loadResponses(taskId: task.id)
        }
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

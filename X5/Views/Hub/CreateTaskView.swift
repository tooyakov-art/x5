import SwiftUI

struct CreateTaskView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void = {}

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var budget: String = ""
    @State private var category: String = "marketing"
    @State private var countryCode: String = "KZ"
    @State private var city: String = ""
    @State private var deadline: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var hasDeadline: Bool = false
    @State private var saving: Bool = false
    @State private var errorMessage: String?

    @StateObject private var hub = HubService()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(loc.t("task_section"))) {
                    TextField("Заголовок", text: $title)
                    TextField("Описание", text: $description, axis: .vertical).lineLimit(3...8)
                }
                Section(header: Text(loc.t("task_budget_category"))) {
                    TextField("Бюджет (например 50 000 ₸)", text: $budget)
                    Picker("Категория", selection: $category) {
                        ForEach(HubCategories.all) { cat in
                            Text("\(cat.emoji)  \(cat.labelEn)").tag(cat.id)
                        }
                    }
                    Toggle("Срок", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Срок", selection: $deadline, displayedComponents: .date)
                    }
                }
                Section(header: Text("Локация выполнения")) {
                    Picker("Страна", selection: $countryCode) {
                        ForEach(CISLocations.countries, id: \.code) { country in
                            Text(country.name).tag(country.code)
                        }
                    }
                    TextField("Город", text: $city)
                        .textContentType(.addressCity)

                    let suggestions = CISLocations.search(country: countryCode, query: city)
                    if !suggestions.isEmpty && !suggestions.contains(where: { $0.city.caseInsensitiveCompare(city) == .orderedSame }) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions) { item in
                                    Button(item.city) { city = item.city }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                if let err = errorMessage {
                    Section { Text(err).foregroundColor(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(X5Background())
            .navigationTitle("Новая задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("btn_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if saving { ProgressView() } else { Text(loc.t("common_post")).bold() }
                    }
                    .disabled(saving || !canSubmit)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let profileCountry = currentUser.profile?.countryCode, !profileCountry.isEmpty {
                countryCode = profileCountry
            }
            if city.isEmpty { city = currentUser.profile?.city ?? "" }
        }
        .onChange(of: countryCode) { _ in
            if countryCode != currentUser.profile?.countryCode { city = "" }
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !budget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !countryCode.isEmpty &&
        city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private func submit() async {
        guard let uid = auth.userId, let token = await auth.freshAccessToken() else { return }
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
            countryCode: countryCode,
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
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

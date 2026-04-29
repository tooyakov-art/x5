import SwiftUI

/// Standard SwiftUI TabView shell. Default style, no custom theming —
/// just adds bottom tab navigation around the existing MainView.
struct RootTabView: View {
    var body: some View {
        TabView {
            MainView()
                .tabItem {
                    Label("Captions", systemImage: "text.alignleft")
                }

            ImagesTabView()
                .tabItem {
                    Label("Images", systemImage: "photo.on.rectangle")
                }

            ChatsTabView()
                .tabItem {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                }

            CoursesTabView()
                .tabItem {
                    Label("Courses", systemImage: "graduationcap")
                }
        }
    }
}

// MARK: - Stub tabs (functionality TBD)

private struct ImagesTabView: View {
    @State private var prompt: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ComingSoon(systemImage: "photo.on.rectangle.angled",
                           title: "Image generation",
                           subtitle: "Type a prompt, get marketing-ready images.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("PROMPT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.55))
                    TextField("e.g. cozy coffee shop on a rainy morning",
                              text: $prompt, axis: .vertical)
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                        .frame(minHeight: 64, alignment: .top)
                        .lineLimit(2...4)
                    Button {} label: {
                        Text("Generate (coming soon)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(14)
                    }
                    .disabled(true)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Images")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct ChatsTabView: View {
    var body: some View {
        NavigationStack {
            VStack {
                ComingSoon(systemImage: "bubble.left.and.bubble.right",
                           title: "Marketing chats",
                           subtitle: "Brainstorm campaigns and ask anything about marketing.")
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Chats")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct CoursesTabView: View {
    private let lessons: [(String, String)] = [
        ("Marketing 101", "Foundation: positioning, messaging, audience."),
        ("Brand voice", "Find your tone and lock it across content."),
        ("Funnel basics", "Plan an end-to-end customer funnel."),
        ("Ad copy patterns", "10 proven ad copy structures.")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(lessons.enumerated()), id: \.offset) { _, l in
                        HStack(spacing: 14) {
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.0).foregroundColor(.white)
                                Text(l.1)
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("More lessons coming soon.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.04, blue: 0.07))
            .navigationTitle("Courses")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Shared placeholder

private struct ComingSoon: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Coming soon")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(Capsule())
        }
    }
}

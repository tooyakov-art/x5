import SwiftUI

struct Course: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let durationMinutes: Int
    let icon: String
    let lessons: [String]
    let proOnly: Bool
}

private let demoCourses: [Course] = [
    Course(
        title: "Marketing 101",
        summary: "Foundation: positioning, messaging, audience.",
        durationMinutes: 35,
        icon: "lightbulb",
        lessons: ["Why positioning beats budget", "Pick a wedge audience", "Write the one-liner"],
        proOnly: false
    ),
    Course(
        title: "Brand voice in 30 minutes",
        summary: "Find your tone and lock it across every channel.",
        durationMinutes: 30,
        icon: "speaker.wave.2",
        lessons: ["Voice axes", "Word lists do/don't", "Audit your last 10 posts"],
        proOnly: false
    ),
    Course(
        title: "Funnel basics",
        summary: "Plan an end-to-end customer funnel.",
        durationMinutes: 45,
        icon: "chart.bar",
        lessons: ["Awareness → Consideration → Decision", "Channel selection", "Measuring honestly"],
        proOnly: true
    ),
    Course(
        title: "Ad copy patterns",
        summary: "10 proven ad copy structures with breakdowns.",
        durationMinutes: 50,
        icon: "doc.text",
        lessons: ["PAS · AIDA · BAB", "Specificity beats clever", "Headline tests"],
        proOnly: true
    ),
    Course(
        title: "Launch playbook",
        summary: "Run a tight launch in two weeks.",
        durationMinutes: 60,
        icon: "rocket",
        lessons: ["Asset checklist", "Day-by-day plan", "Post-launch review"],
        proOnly: true
    )
]

struct CoursesView: View {
    @EnvironmentObject private var sub: Subscription
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(demoCourses) { course in
                        NavigationLink {
                            CourseDetailView(course: course, openPaywall: { showingPaywall = true })
                        } label: {
                            CourseRow(course: course)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Courses")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !sub.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingPaywall = true } label: {
                            Text("Pro")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }
}

private struct CourseRow: View {
    let course: Course

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: course.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(course.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    if course.proOnly {
                        Text("PRO")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                    }
                }
                Text(course.summary)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
                Text("\(course.durationMinutes) min · \(course.lessons.count) lessons")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CourseDetailView: View {
    let course: Course
    var openPaywall: () -> Void

    @EnvironmentObject private var sub: Subscription
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: course.icon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.accentColor)

                Text(course.title)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)

                Text(course.summary)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.65))

                Text("LESSONS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(Array(course.lessons.enumerated()), id: \.offset) { idx, lesson in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.accentColor)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.14))
                                .clipShape(Circle())
                            Text(lesson)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if course.proOnly && !sub.isPro {
                    Button(action: openPaywall) {
                        Text("Unlock with Pro")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                } else {
                    Button {
                        // Stub: start course
                    } label: {
                        Text("Start course")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
        .navigationTitle("")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

import SwiftUI

struct ExperimentalCoursesView: View {
    private let courses = [
        ("Marketing 101", "Foundation course on positioning and messaging.", Color(red: 0.16, green: 0.41, blue: 0.96)),
        ("Brand voice", "How to find and lock your brand's voice.", Color(red: 0.6, green: 0.32, blue: 0.92)),
        ("Funnel basics", "Plan an end-to-end customer funnel.", Color(red: 0.13, green: 0.7, blue: 0.45)),
        ("Ad copy patterns", "10 proven ad copy structures.", Color(red: 0.93, green: 0.34, blue: 0.62))
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LEARN")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(Color(red: 0.55, green: 0.6, blue: 0.7))
                    Text("Courses")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                    Text("Bite-sized lessons for marketers.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))
                }

                ForEach(Array(courses.enumerated()), id: \.offset) { _, course in
                    GlassCard {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(course.2.opacity(0.15))
                                Image(systemName: "graduationcap.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(course.2)
                            }
                            .frame(width: 56, height: 56)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(course.0)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
                                Text(course.1)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.45, green: 0.5, blue: 0.6))
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
    }
}

import SwiftUI

struct Specialist: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let rate: String
    let bio: String
    let initials: String
    let tint: Color
}

private let demoSpecialists: [Specialist] = [
    Specialist(
        name: "Aisha K.",
        role: "Brand strategist",
        rate: "$60 / hour",
        bio: "10 yrs in DTC and hospitality. Helps founders define a wedge audience and ship the one-liner that sells.",
        initials: "AK",
        tint: Color(red: 0.6, green: 0.32, blue: 0.92)
    ),
    Specialist(
        name: "Marat S.",
        role: "Performance marketer",
        rate: "$55 / hour",
        bio: "Meta + Google ads operator. Has scaled SaaS, e-com and local services in CIS and MENA markets.",
        initials: "MS",
        tint: Color(red: 0.16, green: 0.41, blue: 0.96)
    ),
    Specialist(
        name: "Dasha P.",
        role: "Content writer",
        rate: "$40 / hour",
        bio: "Long-form blog + LinkedIn ghostwriter. Bilingual EN/RU. Story-led editorial style.",
        initials: "DP",
        tint: Color(red: 0.93, green: 0.34, blue: 0.62)
    ),
    Specialist(
        name: "Timur B.",
        role: "Designer",
        rate: "$50 / hour",
        bio: "Brand identity, social tiles, product launch decks. Turns half-formed ideas into shippable artwork in days.",
        initials: "TB",
        tint: Color(red: 0.13, green: 0.7, blue: 0.45)
    )
]

struct HireView: View {
    @EnvironmentObject private var sub: Subscription
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !sub.isPro {
                        ProBanner(action: { showingPaywall = true })
                    }

                    Text("VETTED MARKETERS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 4)

                    ForEach(demoSpecialists) { person in
                        SpecialistRow(person: person, locked: !sub.isPro, openPaywall: { showingPaywall = true })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Hub")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }
}

private struct ProBanner: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hiring requires Pro").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    Text("Unlock to chat with vetted marketers.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SpecialistRow: View {
    let person: Specialist
    let locked: Bool
    let openPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(person.tint)
                    Text(person.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text(person.role).font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Text(person.rate)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            Text(person.bio)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(3)

            Button(action: { locked ? openPaywall() : nil }) {
                Text(locked ? "Unlock to contact" : "Contact")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(locked ? .black : .accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(locked ? Color.accentColor : Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

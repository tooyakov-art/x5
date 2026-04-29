import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var sub: Subscription
    @State private var draft: String = ""
    @State private var messages: [ChatMessage] = ChatMessage.welcome
    @State private var showingPaywall = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                Bubble(message: msg).id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Ask about marketing…", text: $draft, axis: .vertical)
                        .focused($inputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(20)
                        .lineLimit(1...4)

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend ? .accentColor : .white.opacity(0.2))
                    }
                    .disabled(!canSend)
                }
                .padding(12)
                .background(Color(red: 0.04, green: 0.04, blue: 0.07))
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !sub.isPro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("Pro", systemImage: "sparkles")
                                .labelStyle(.titleOnly)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        inputFocused = false
        // Stub assistant reply
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let reply: String = sub.isPro
                ? "Marketing chat is rolling out next week. Your message is saved."
                : "Marketing chat is a Pro feature. Tap the Pro badge to unlock."
            messages.append(ChatMessage(role: .assistant, text: reply))
        }
    }
}

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String

    static let welcome: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Hi! I'm your marketing chat. Ask anything — campaign ideas, copy, channel choice, brand voice. (Replies powered by humans for now — full automation rolls out next.)")
    ]
}

private struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

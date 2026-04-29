import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: CaptionHistory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.items.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.accentColor)
                        Text("No history yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Generated captions appear here.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.04, green: 0.04, blue: 0.07))
                } else {
                    List {
                        ForEach(history.items) { item in
                            Section {
                                ForEach(Array(item.captions.enumerated()), id: \.offset) { _, caption in
                                    Text(caption)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .swipeActions {
                                            Button {
                                                UIPasteboard.general.string = caption
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                            .tint(.blue)
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(item.topic).foregroundColor(.white)
                                    Spacer()
                                    Text("\(item.tone) · \(item.platform)")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(red: 0.04, green: 0.04, blue: 0.07))
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if !history.items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") { history.clear() }
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

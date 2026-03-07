import SwiftUI

struct AddBookView: View {
    @Environment(\.dismiss) var dismiss
    let onComplete: () async -> Void

    @State private var title = ""
    @State private var author = ""
    @State private var firstPage = "1"
    @State private var lastPage = ""
    @State private var difficulty = "average"
    @State private var isLoading = false
    @State private var error: String?

    let difficulties = ["easy", "below_average", "average", "challenging", "dense"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Book Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                }

                Section("Pages") {
                    TextField("First Page", text: $firstPage)
                        .keyboardType(.numberPad)
                    TextField("Last Page", text: $lastPage)
                        .keyboardType(.numberPad)
                }

                Section("Difficulty") {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(difficulties, id: \.self) { d in
                            Text(d.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await createBook() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Add Book")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(title.isEmpty || lastPage.isEmpty || isLoading)
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    func createBook() async {
        isLoading = true
        do {
            let params = BookCreateParams(
                title: title,
                author: author.isEmpty ? nil : author,
                firstPage: Int(firstPage) ?? 1,
                lastPage: Int(lastPage) ?? 0,
                wordsPerPage: nil,
                difficulty: difficulty,
                coverImageUrl: nil,
                isbn: nil
            )
            _ = try await APIClient.shared.createBook(params)
            await onComplete()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

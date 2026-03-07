import Foundation

@MainActor
final class BooksViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var selectedFilter: String? = nil
    @Published var isLoading = false
    @Published var error: String?

    let filters = ["All", "Reading", "Unread", "Completed", "Abandoned"]

    var filteredBooks: [Book] {
        guard let filter = selectedFilter, filter != "All" else { return books }
        return books.filter { $0.status == filter.lowercased() }
    }

    func load() async {
        isLoading = true
        do {
            let response = try await APIClient.shared.fetchBooks()
            books = response.books
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func startReading(book: Book) async {
        do {
            let response = try await APIClient.shared.startReading(bookId: book.id)
            updateBook(response.book)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markCompleted(book: Book) async {
        do {
            let response = try await APIClient.shared.markBookCompleted(bookId: book.id)
            updateBook(response.book)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteBook(_ book: Book) async {
        do {
            try await APIClient.shared.deleteBook(id: book.id)
            books.removeAll { $0.id == book.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateBook(_ updated: Book) {
        if let idx = books.firstIndex(where: { $0.id == updated.id }) {
            books[idx] = updated
        }
    }
}

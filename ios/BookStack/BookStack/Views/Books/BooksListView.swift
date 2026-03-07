import SwiftUI

struct BooksListView: View {
    @StateObject private var viewModel = BooksViewModel()
    @State private var showAddBook = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.filters, id: \.self) { filter in
                            FilterChip(
                                title: filter,
                                isSelected: (viewModel.selectedFilter ?? "All") == filter
                            ) {
                                viewModel.selectedFilter = filter == "All" ? nil : filter
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                List {
                    ForEach(viewModel.filteredBooks) { book in
                        NavigationLink(destination: BookDetailView(bookId: book.id)) {
                            BookRow(book: book)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteBook(book) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if book.isUnread {
                                Button {
                                    Task { await viewModel.startReading(book: book) }
                                } label: {
                                    Label("Start", systemImage: "book.fill")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Books")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddBook = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView { await viewModel.load() }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
        }
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            // Cover or placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 56)
                .overlay {
                    if let url = book.coverImageUrl, let imageUrl = URL(string: url) {
                        AsyncImage(url: imageUrl) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    StatusBadge(status: book.status)

                    if book.isReading {
                        Text("\(Int(book.progressPercentage))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if book.isReading {
                CircularProgress(progress: book.progressPercentage / 100)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: String

    var color: Color {
        switch status {
        case "reading": return .green
        case "completed": return .blue
        case "unread": return .gray
        case "abandoned": return .red
        default: return .secondary
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

struct CircularProgress: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

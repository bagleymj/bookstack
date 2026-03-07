import Foundation

// MARK: - Auth

struct AuthResponse: Codable {
    let user: AuthUser
    let token: String
    let message: String
}

struct AuthUser: Codable {
    let id: Int
    let email: String
    let name: String?
}

struct AuthError: Codable {
    let error: String?
    let errors: [String]?
}

// MARK: - Book

struct Book: Codable, Identifiable {
    let id: Int
    let title: String
    let author: String?
    let firstPage: Int
    let lastPage: Int
    let currentPage: Int
    let totalPages: Int
    let remainingPages: Int
    let progressPercentage: Double
    let wordsPerPage: Int?
    let difficulty: String
    let status: String
    let coverImageUrl: String?
    let isbn: String?
    let estimatedReadingTimeMinutes: Int
    let actualWpm: Double?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, author, difficulty, status, isbn
        case firstPage = "first_page"
        case lastPage = "last_page"
        case currentPage = "current_page"
        case totalPages = "total_pages"
        case remainingPages = "remaining_pages"
        case progressPercentage = "progress_percentage"
        case wordsPerPage = "words_per_page"
        case coverImageUrl = "cover_image_url"
        case estimatedReadingTimeMinutes = "estimated_reading_time_minutes"
        case actualWpm = "actual_wpm"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isReading: Bool { status == "reading" }
    var isCompleted: Bool { status == "completed" }
    var isUnread: Bool { status == "unread" }
}

struct BookResponse: Codable {
    let book: Book
}

struct BooksResponse: Codable {
    let books: [Book]
}

struct BookDetailResponse: Codable {
    let book: Book
    let activeGoal: ReadingGoal?
    let recentSessions: [ReadingSession]

    enum CodingKeys: String, CodingKey {
        case book
        case activeGoal = "active_goal"
        case recentSessions = "recent_sessions"
    }
}

struct BookCreateParams: Codable {
    let title: String
    let author: String?
    let firstPage: Int
    let lastPage: Int
    let wordsPerPage: Int?
    let difficulty: String
    let coverImageUrl: String?
    let isbn: String?

    enum CodingKeys: String, CodingKey {
        case title, author, difficulty, isbn
        case firstPage = "first_page"
        case lastPage = "last_page"
        case wordsPerPage = "words_per_page"
        case coverImageUrl = "cover_image_url"
    }
}

// MARK: - Reading Session

struct ReadingSession: Codable, Identifiable {
    let id: Int
    let bookId: Int
    let bookTitle: String
    let startedAt: String
    let endedAt: String?
    let startPage: Int
    let endPage: Int?
    let durationSeconds: Int?
    let pagesRead: Int?
    let wordsPerMinute: Double?
    let inProgress: Bool
    let untracked: Bool
    let formattedDuration: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case bookId = "book_id"
        case bookTitle = "book_title"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case startPage = "start_page"
        case endPage = "end_page"
        case durationSeconds = "duration_seconds"
        case pagesRead = "pages_read"
        case wordsPerMinute = "words_per_minute"
        case inProgress = "in_progress"
        case untracked
        case formattedDuration = "formatted_duration"
        case createdAt = "created_at"
    }

    var startedAtDate: Date? {
        ISO8601DateFormatter.flexible.date(from: startedAt)
    }

    var elapsedSeconds: TimeInterval? {
        guard let start = startedAtDate else { return nil }
        if let end_ = endedAt, let endDate = ISO8601DateFormatter.flexible.date(from: end_) {
            return endDate.timeIntervalSince(start)
        }
        return Date().timeIntervalSince(start)
    }
}

struct ReadingSessionResponse: Codable {
    let readingSession: ReadingSession?

    enum CodingKeys: String, CodingKey {
        case readingSession = "reading_session"
    }
}

struct ReadingSessionsResponse: Codable {
    let readingSessions: [ReadingSession]

    enum CodingKeys: String, CodingKey {
        case readingSessions = "reading_sessions"
    }
}

// MARK: - Reading Goal

struct ReadingGoal: Codable, Identifiable {
    let id: Int
    let bookId: Int
    let bookTitle: String
    let startedOn: String?
    let targetCompletionDate: String?
    let includeWeekends: Bool
    let status: String
    let progressPercentage: Double
    let pagesPerDay: Int
    let minutesPerDay: Int
    let daysRemaining: Int
    let onTrack: Bool
    let trackingStatus: String?
    let position: Int?
    let autoScheduled: Bool
    let hasUnresolvedDiscrepancy: Bool
    let createdAt: String
    let updatedAt: String
    let todayQuota: DailyQuota?
    let dailyQuotas: [DailyQuota]?

    enum CodingKeys: String, CodingKey {
        case id, status, position
        case bookId = "book_id"
        case bookTitle = "book_title"
        case startedOn = "started_on"
        case targetCompletionDate = "target_completion_date"
        case includeWeekends = "include_weekends"
        case progressPercentage = "progress_percentage"
        case pagesPerDay = "pages_per_day"
        case minutesPerDay = "minutes_per_day"
        case daysRemaining = "days_remaining"
        case onTrack = "on_track"
        case trackingStatus = "tracking_status"
        case autoScheduled = "auto_scheduled"
        case hasUnresolvedDiscrepancy = "has_unresolved_discrepancy"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case todayQuota = "today_quota"
        case dailyQuotas = "daily_quotas"
    }
}

struct ReadingGoalResponse: Codable {
    let readingGoal: ReadingGoal

    enum CodingKeys: String, CodingKey {
        case readingGoal = "reading_goal"
    }
}

struct ReadingGoalsResponse: Codable {
    let readingGoals: [ReadingGoal]

    enum CodingKeys: String, CodingKey {
        case readingGoals = "reading_goals"
    }
}

// MARK: - Daily Quota

struct DailyQuota: Codable, Identifiable {
    let id: Int
    let readingGoalId: Int
    let date: String
    let targetPages: Int
    let actualPages: Int
    let status: String
    let pagesRemaining: Int
    let percentageComplete: Int
    let effectivelyComplete: Bool
    let estimatedMinutesRemaining: Int
    let bookTitle: String?
    let bookId: Int?
    let goalId: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, status
        case readingGoalId = "reading_goal_id"
        case targetPages = "target_pages"
        case actualPages = "actual_pages"
        case pagesRemaining = "pages_remaining"
        case percentageComplete = "percentage_complete"
        case effectivelyComplete = "effectively_complete"
        case estimatedMinutesRemaining = "estimated_minutes_remaining"
        case bookTitle = "book_title"
        case bookId = "book_id"
        case goalId = "goal_id"
    }
}

struct DailyQuotaResponse: Codable {
    let dailyQuota: DailyQuota

    enum CodingKeys: String, CodingKey {
        case dailyQuota = "daily_quota"
    }
}

// MARK: - Dashboard

struct DashboardResponse: Codable {
    let today: TodayData
    let stats: StatsData
    let discrepancies: [Discrepancy]
}

struct TodayData: Codable {
    let quotas: [DailyQuota]
    let pagesRead: Int
    let readingTimeSeconds: Int
    let totalMinutesRemaining: Int
    let activeSession: ReadingSession?

    enum CodingKeys: String, CodingKey {
        case quotas
        case pagesRead = "pages_read"
        case readingTimeSeconds = "reading_time_seconds"
        case totalMinutesRemaining = "total_minutes_remaining"
        case activeSession = "active_session"
    }
}

struct StatsData: Codable {
    let readingStreak: Int
    let booksInProgress: Int
    let booksCompletedAllTime: Int
    let yearlyBooksScheduled: Int
    let yearlyBooksCompleted: Int
    let pagesThisWeek: Int
    let timeThisWeekSeconds: Int
    let averageWpm: Double?
    let totalSessions: Int
    let totalPagesRead: Int
    let totalReadingTimeFormatted: String

    enum CodingKeys: String, CodingKey {
        case readingStreak = "reading_streak"
        case booksInProgress = "books_in_progress"
        case booksCompletedAllTime = "books_completed_all_time"
        case yearlyBooksScheduled = "yearly_books_scheduled"
        case yearlyBooksCompleted = "yearly_books_completed"
        case pagesThisWeek = "pages_this_week"
        case timeThisWeekSeconds = "time_this_week_seconds"
        case averageWpm = "average_wpm"
        case totalSessions = "total_sessions"
        case totalPagesRead = "total_pages_read"
        case totalReadingTimeFormatted = "total_reading_time_formatted"
    }
}

struct Discrepancy: Codable {
    let goalId: Int
    let bookId: Int
    let bookTitle: String
    let type: String
    let pages: Int

    enum CodingKeys: String, CodingKey {
        case goalId = "goal_id"
        case bookId = "book_id"
        case bookTitle = "book_title"
        case type, pages
    }
}

// MARK: - Profile

struct ProfileResponse: Codable {
    let profile: UserProfile
}

struct UserProfile: Codable {
    let id: Int
    let email: String
    let name: String?
    let defaultWordsPerPage: Int
    let defaultReadingSpeedWpm: Int
    let effectiveReadingSpeed: Double
    let maxConcurrentBooks: Int
    let weekdayReadingMinutes: Int
    let weekendReadingMinutes: Int
    let includesWeekends: Bool
    let stats: ProfileStats?

    enum CodingKeys: String, CodingKey {
        case id, email, name, stats
        case defaultWordsPerPage = "default_words_per_page"
        case defaultReadingSpeedWpm = "default_reading_speed_wpm"
        case effectiveReadingSpeed = "effective_reading_speed"
        case maxConcurrentBooks = "max_concurrent_books"
        case weekdayReadingMinutes = "weekday_reading_minutes"
        case weekendReadingMinutes = "weekend_reading_minutes"
        case includesWeekends = "includes_weekends"
    }
}

struct ProfileStats: Codable {
    let totalSessions: Int
    let totalPagesRead: Int
    let totalReadingTimeSeconds: Int
    let totalReadingTimeFormatted: String
    let averageWpm: Double?
    let lastCalculatedAt: String?

    enum CodingKeys: String, CodingKey {
        case totalSessions = "total_sessions"
        case totalPagesRead = "total_pages_read"
        case totalReadingTimeSeconds = "total_reading_time_seconds"
        case totalReadingTimeFormatted = "total_reading_time_formatted"
        case averageWpm = "average_wpm"
        case lastCalculatedAt = "last_calculated_at"
    }
}

// MARK: - Pipeline

struct PipelineResponse: Codable {
    let pipeline: PipelineInfo
    let goals: [PipelineGoal]
}

struct PipelineInfo: Codable {
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct PipelineGoal: Codable, Identifiable {
    let id: Int
    let bookId: Int
    let title: String
    let author: String?
    let startDate: String?
    let endDate: String?
    let progress: Double
    let status: String
    let difficulty: String
    let totalPages: Int
    let estimatedMinutes: Int
    let minutesPerDay: Int
    let durationDays: Int
    let daysRemaining: Int
    let includeWeekends: Bool
    let goalStatus: String
    let onTrack: Bool
    let pagesPerDay: Int

    enum CodingKeys: String, CodingKey {
        case id, title, author, progress, status, difficulty
        case bookId = "book_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case totalPages = "total_pages"
        case estimatedMinutes = "estimated_minutes"
        case minutesPerDay = "minutes_per_day"
        case durationDays = "duration_days"
        case daysRemaining = "days_remaining"
        case includeWeekends = "include_weekends"
        case goalStatus = "goal_status"
        case onTrack = "on_track"
        case pagesPerDay = "pages_per_day"
    }
}

// MARK: - Helpers

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct ErrorResponse: Codable {
    let error: String?
    let errors: [String]?

    var message: String {
        error ?? errors?.joined(separator: ", ") ?? "Unknown error"
    }
}

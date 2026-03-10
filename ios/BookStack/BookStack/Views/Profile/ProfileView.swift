import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var profile: UserProfile?
    @State private var isLoading = false
    @State private var isEditing = false

    // Edit state
    @State private var name = ""
    @State private var wordsPerPage = ""
    @State private var readingSpeedWpm = ""
    @State private var maxConcurrentBooks = ""
    @State private var weekdayMinutes = ""
    @State private var weekendMinutes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let profile = profile {
                    Section("Account") {
                        LabeledContent("Email", value: profile.email)
                        if isEditing {
                            TextField("Name", text: $name)
                        } else {
                            LabeledContent("Name", value: profile.name ?? "-")
                        }
                    }

                    Section("Reading Preferences") {
                        if isEditing {
                            TextField("Words per Page", text: $wordsPerPage)
                                .keyboardType(.numberPad)
                            TextField("Est. Reading Speed (WPM)", text: $readingSpeedWpm)
                                .keyboardType(.numberPad)
                            TextField("Max Concurrent Books", text: $maxConcurrentBooks)
                                .keyboardType(.numberPad)
                        } else {
                            LabeledContent("Words/Page", value: "\(profile.defaultWordsPerPage)")
                            LabeledContent("Est. Reading Speed", value: "\(profile.defaultReadingSpeedWpm) WPM")
                            LabeledContent("Effective Speed", value: "\(Int(profile.effectiveReadingSpeed)) WPM")
                            LabeledContent("Max Concurrent", value: "\(profile.maxConcurrentBooks)")
                        }
                    }

                    Section("Schedule") {
                        if isEditing {
                            TextField("Weekday Minutes", text: $weekdayMinutes)
                                .keyboardType(.numberPad)
                            TextField("Weekend Minutes", text: $weekendMinutes)
                                .keyboardType(.numberPad)
                        } else {
                            LabeledContent("Weekday", value: "\(profile.weekdayReadingMinutes) min")
                            LabeledContent("Weekend", value: "\(profile.weekendReadingMinutes) min")
                        }
                    }

                    if let stats = profile.stats {
                        Section("Stats") {
                            LabeledContent("Total Sessions", value: "\(stats.totalSessions)")
                            LabeledContent("Total Pages", value: "\(stats.totalPagesRead)")
                            LabeledContent("Total Time", value: stats.totalReadingTimeFormatted)
                            LabeledContent("Avg WPM", value: stats.averageWpm.map { "\(Int($0))" } ?? "-")
                        }
                    }

                    if let error = error {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            Task { await authManager.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.forward")
                        }
                    }
                } else if isLoading {
                    ProgressView()
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            Task { await saveProfile() }
                        }
                    } else {
                        Button("Edit") {
                            populateEditFields()
                            isEditing = true
                        }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isEditing = false
                        }
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    func load() async {
        isLoading = true
        do {
            let response = try await APIClient.shared.fetchProfile()
            profile = response.profile
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func populateEditFields() {
        guard let p = profile else { return }
        name = p.name ?? ""
        wordsPerPage = "\(p.defaultWordsPerPage)"
        readingSpeedWpm = "\(p.defaultReadingSpeedWpm)"
        maxConcurrentBooks = "\(p.maxConcurrentBooks)"
        weekdayMinutes = "\(p.weekdayReadingMinutes)"
        weekendMinutes = "\(p.weekendReadingMinutes)"
    }

    func saveProfile() async {
        var params: [String: Any] = [:]
        params["name"] = name
        if let v = Int(wordsPerPage) { params["default_words_per_page"] = v }
        if let v = Int(readingSpeedWpm) { params["default_reading_speed_wpm"] = v }
        if let v = Int(maxConcurrentBooks) { params["max_concurrent_books"] = v }
        if let v = Int(weekdayMinutes) { params["weekday_reading_minutes"] = v }
        if let v = Int(weekendMinutes) { params["weekend_reading_minutes"] = v }

        do {
            let response = try await APIClient.shared.updateProfile(params: params)
            profile = response.profile
            isEditing = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

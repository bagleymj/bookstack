require "rails_helper"

RSpec.describe Book, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "requires a title" do
      book = build(:book, user: user, title: nil)
      expect(book).not_to be_valid
    end

    it "requires first_page > 0" do
      book = build(:book, user: user, first_page: 0)
      expect(book).not_to be_valid
    end

    it "requires last_page > 0" do
      book = build(:book, user: user, last_page: 0)
      expect(book).not_to be_valid
    end

    it "requires last_page >= first_page" do
      book = build(:book, user: user, first_page: 100, last_page: 50)
      expect(book).not_to be_valid
      expect(book.errors[:last_page]).to include("must be greater than or equal to first page")
    end

    it "allows last_page equal to first_page" do
      book = build(:book, user: user, first_page: 1, last_page: 1)
      expect(book).to be_valid
    end
  end

  describe "set_defaults" do
    it "advances current_page when first_page is raised past it" do
      book = create(:book, user: user, first_page: 1, last_page: 300, current_page: 1)
      book.update!(first_page: 31)
      expect(book.current_page).to eq(31)
    end

    it "does not move current_page when first_page is lowered but user has read ahead" do
      book = create(:book, user: user, first_page: 20, last_page: 300, current_page: 50)
      book.update!(first_page: 10)
      expect(book.current_page).to eq(50)
    end

    it "resets current_page when first_page is lowered and user hasn't read past start" do
      book = create(:book, user: user, first_page: 5, last_page: 300, current_page: 5)
      book.update!(first_page: 1)
      expect(book.current_page).to eq(1)
    end

    it "does not move current_page when it is already past first_page" do
      book = create(:book, user: user, first_page: 1, last_page: 300, current_page: 100)
      book.update!(first_page: 50)
      expect(book.current_page).to eq(100)
    end

    it "yields correct remaining_pages after first_page adjustment" do
      book = create(:book, user: user, first_page: 1, last_page: 312, current_page: 1)
      book.update!(first_page: 31)
      expect(book.remaining_pages).to eq(312 - 31)
    end

    it "yields non-negative progress after first_page adjustment" do
      book = create(:book, user: user, first_page: 1, last_page: 312, current_page: 1)
      book.update!(first_page: 31)
      expect(book.progress_percentage).to be >= 0
    end

    it "defaults density to average" do
      book = create(:book, user: user, density: nil)
      expect(book.density).to eq("average")
    end

    it "defaults first_page to 1" do
      book = Book.new(user: user, title: "Test", last_page: 100)
      book.valid?
      expect(book.first_page).to eq(1)
    end
  end

  describe "#total_pages" do
    it "returns last_page - first_page + 1" do
      book = create(:book, user: user, first_page: 1, last_page: 300)
      expect(book.total_pages).to eq(300)
    end

    it "handles non-1 first page" do
      book = create(:book, user: user, first_page: 11, last_page: 300)
      expect(book.total_pages).to eq(290)
    end
  end

  describe "#remaining_pages" do
    it "returns last_page minus current_page" do
      book = create(:book, user: user, first_page: 1, last_page: 300, current_page: 100)
      expect(book.remaining_pages).to eq(200)
    end

    it "returns 0 when current_page equals last_page" do
      book = create(:book, user: user, first_page: 1, last_page: 300, current_page: 300)
      expect(book.remaining_pages).to eq(0)
    end
  end

  describe "#progress_percentage" do
    it "returns 0 at the start" do
      book = create(:book, user: user, first_page: 1, last_page: 300, current_page: 1)
      expect(book.progress_percentage).to eq(0.0)
    end

    it "returns 50 at the midpoint" do
      book = create(:book, user: user, first_page: 1, last_page: 201, current_page: 101)
      expect(book.progress_percentage).to eq(50.0)
    end

    it "returns 100 at the end" do
      book = create(:book, user: user, first_page: 1, last_page: 300, current_page: 300)
      expect(book.progress_percentage).to eq(100.0)
    end

    it "handles first_page > 1" do
      book = create(:book, user: user, first_page: 11, last_page: 111, current_page: 61)
      expect(book.progress_percentage).to eq(50.0)
    end

    it "handles edge case where first_page equals last_page" do
      book = create(:book, user: user, first_page: 1, last_page: 1, current_page: 1)
      expect(book.progress_percentage).to eq(0) # range is 0
    end
  end

  describe "#density_modifier" do
    it "returns the DENSITY_MODIFIERS value for the density enum" do
      book = build(:book, density: :light)
      expect(book.density_modifier).to eq(1.3)
    end

    it "returns actual_density_modifier when set" do
      book = build(:book, density: :average, actual_density_modifier: 0.9)
      expect(book.density_modifier).to eq(0.9)
    end

    it "falls back to enum modifier when actual is nil" do
      book = build(:book, density: :dense, actual_density_modifier: nil)
      expect(book.density_modifier).to eq(0.7)
    end
  end

  describe "#actual_wpm" do
    it "returns nil with no sessions" do
      book = create(:book, user: user)
      expect(book.actual_wpm).to be_nil
    end

    it "returns average WPM from completed tracked sessions" do
      book = create(:book, :reading, user: user)
      # WPM is recalculated by calculate_metrics callback, so set consistent values:
      # 10 pages * 250 words = 2500 words / 10 min = 250 WPM
      create(:reading_session, :completed, user: user, book: book,
             start_page: 1, end_page: 11, duration_seconds: 600)
      # 10 pages * 250 words = 2500 words / 5 min = 500 WPM
      create(:reading_session, :completed, user: user, book: book,
             start_page: 11, end_page: 21, duration_seconds: 300)

      # Database average of (250 + 500) / 2 = 375
      expect(book.actual_wpm).to eq(375.0)
    end
  end

  describe "#start_reading!" do
    it "changes status from unread to reading" do
      book = create(:book, :unread, user: user)
      book.start_reading!
      expect(book.reload.status).to eq("reading")
    end

    it "does nothing if already reading" do
      book = create(:book, :reading, user: user)
      expect { book.start_reading! }.not_to change { book.reload.status }
    end
  end

  describe "#mark_completed!" do
    it "sets status to completed" do
      book = create(:book, :reading, user: user)
      book.mark_completed!
      expect(book.reload.status).to eq("completed")
    end

    it "sets current_page to last_page" do
      book = create(:book, :reading, user: user, last_page: 300, current_page: 150)
      book.mark_completed!
      expect(book.reload.current_page).to eq(300)
    end

    it "sets completed_at" do
      book = create(:book, :reading, user: user)
      book.mark_completed!
      expect(book.reload.completed_at).to be_present
    end

    it "marks active reading goals as completed" do
      book = create(:book, :reading, user: user)
      goal = create(:reading_goal, user: user, book: book, status: :active)
      book.mark_completed!
      expect(goal.reload.status).to eq("completed")
    end
  end

  describe "#update_progress!" do
    it "updates current_page" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)
      book.update_progress!(100)
      expect(book.reload.current_page).to eq(100)
    end

    it "caps current_page at last_page" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)
      book.update_progress!(500)
      expect(book.reload.current_page).to eq(300)
    end

    it "marks as completed when reaching last_page" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)
      book.update_progress!(300)
      expect(book.reload.status).to eq("completed")
    end

    it "does not mark completed when below last_page" do
      book = create(:book, :reading, user: user, current_page: 50, last_page: 300)
      book.update_progress!(200)
      expect(book.reload.status).to eq("reading")
    end
  end

  describe "#effective_reading_time_minutes" do
    it "returns 0 when no remaining pages" do
      book = create(:book, :completed, user: user)
      expect(book.effective_reading_time_minutes).to eq(0)
    end

    it "uses actual WPM when sessions exist" do
      book = create(:book, :reading, user: user, first_page: 1, last_page: 100, current_page: 1)
      create(:reading_session, :completed, user: user, book: book,
             start_page: 1, end_page: 11, duration_seconds: 600, words_per_minute: 250)

      minutes = book.effective_reading_time_minutes
      # 99 remaining pages * 250 words / 250 WPM = 99 minutes
      expect(minutes).to eq(99)
    end
  end

  describe "#formatted_estimated_time" do
    it "formats minutes" do
      book = create(:book, :reading, user: user, first_page: 1, last_page: 10, current_page: 1)
      expect(book.formatted_estimated_time).to match(/\d+ min/)
    end
  end

  describe "scopes" do
    before do
      create(:book, :reading, user: user)
      create(:book, :unread, user: user)
      create(:book, :completed, user: user)
    end

    it ".in_progress returns reading books" do
      expect(Book.in_progress.all? { |b| b.status == "reading" }).to be true
    end

    it ".not_started returns unread books" do
      expect(Book.not_started.all? { |b| b.status == "unread" }).to be true
    end

    it ".finished returns completed books" do
      expect(Book.finished.all? { |b| b.status == "completed" }).to be true
    end

    it ".owned returns only owned books" do
      create(:book, :unowned, user: user)
      expect(Book.owned.all?(&:owned?)).to be true
    end

    it ".unowned returns only unowned books" do
      create(:book, :unowned, user: user)
      expect(Book.unowned.none?(&:owned?)).to be true
    end
  end

  describe "callbacks" do
    it "calculates total_pages before save" do
      book = create(:book, user: user, first_page: 1, last_page: 250)
      expect(book.total_pages).to eq(250)
    end

    it "sets completed_at when status changes to completed" do
      book = create(:book, :reading, user: user)
      book.update!(status: :completed, current_page: book.last_page)
      expect(book.completed_at).to be_present
    end

    it "does not override existing completed_at" do
      specific_time = 3.days.ago
      book = create(:book, :reading, user: user)
      book.update!(status: :completed, current_page: book.last_page, completed_at: specific_time)
      expect(book.completed_at).to be_within(1.second).of(specific_time)
    end
  end

  describe "#total_words" do
    it "returns total_pages * WORDS_PER_PAGE" do
      book = create(:book, user: user, first_page: 1, last_page: 100)
      expect(book.total_words).to eq(100 * 250)
    end
  end

  describe "#mark_owned!" do
    it "sets owned to true" do
      book = create(:book, :unowned, user: user)
      book.mark_owned!
      expect(book.reload.owned?).to be true
    end
  end
end

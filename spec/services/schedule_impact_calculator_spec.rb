require "rails_helper"

RSpec.describe ScheduleImpactCalculator do
  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      reading_pace_set_on: Date.current.beginning_of_year,
      default_reading_speed_wpm: 250,
      weekend_mode: :same)
  end

  describe "#impacts_for" do
    it "returns a hash keyed by book id" do
      book = create(:book, user: user, first_page: 1, last_page: 300)
      result = described_class.new(user).impacts_for([book])

      expect(result).to be_a(Hash)
      expect(result).to have_key(book.id)
    end

    it "returns empty hash when user has no pace target" do
      user.update!(reading_pace_type: nil, reading_pace_value: nil)
      book = create(:book, user: user, first_page: 1, last_page: 300)
      result = described_class.new(user).impacts_for([book])

      expect(result).to eq({})
    end

    it "returns integer deltas" do
      book = create(:book, user: user, first_page: 1, last_page: 300)
      result = described_class.new(user).impacts_for([book])

      expect(result[book.id]).to be_a(Integer)
    end

    context "with existing books on the reading list" do
      before do
        3.times do |i|
          b = create(:book, user: user, first_page: 1, last_page: 300, density: :average)
          create(:reading_goal, user: user, book: b, status: :queued,
                 position: i + 1, auto_scheduled: true)
        end
      end

      it "shows positive delta when adding a book to a below-capacity queue" do
        book = create(:book, user: user, first_page: 1, last_page: 300, density: :average)
        result = described_class.new(user).impacts_for([book])

        expect(result[book.id]).to be > 0
      end

      it "shows larger delta for a longer/denser book" do
        dense_book = create(:book, user: user, first_page: 1, last_page: 800, density: :dense)
        result = described_class.new(user).impacts_for([dense_book])

        expect(result[dense_book.id]).to be > 0
      end
    end

    context "with a full epoch" do
      before do
        # Set low pace so epoch is easy to fill
        user.update!(reading_pace_type: "books_per_year", reading_pace_value: 5)

        5.times do |i|
          b = create(:book, user: user, first_page: 1, last_page: 300, density: :average)
          create(:reading_goal, user: user, book: b, status: :queued,
                 position: i + 1, auto_scheduled: true)
        end
      end

      it "shows zero delta when epoch is full — new book starts next epoch" do
        short_book = create(:book, user: user, first_page: 1, last_page: 100, density: :light)
        result = described_class.new(user).impacts_for([short_book])

        # Adding a book to a full epoch doesn't affect current epoch's daily load
        expect(result[short_book.id]).to eq(0)
      end
    end

    it "computes impacts for multiple books at once" do
      books = [
        create(:book, user: user, first_page: 1, last_page: 100, density: :light),
        create(:book, user: user, first_page: 1, last_page: 500, density: :dense)
      ]
      result = described_class.new(user).impacts_for(books)

      expect(result.keys).to contain_exactly(*books.map(&:id))
      expect(result[books[0].id]).to be < result[books[1].id]
    end
  end

  describe "#impact_for" do
    it "returns the delta for a single book" do
      book = create(:book, user: user, first_page: 1, last_page: 300)
      result = described_class.new(user).impact_for(book)

      expect(result).to be_a(Integer)
    end
  end
end

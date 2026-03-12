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

      it "shows positive delta for a longer/denser book" do
        dense_book = create(:book, user: user, first_page: 1, last_page: 800, density: :dense)
        result = described_class.new(user).impacts_for([dense_book])

        expect(result[dense_book.id]).to be > 0
      end

      it "shows negative delta for a shorter/lighter book" do
        light_book = create(:book, user: user, first_page: 1, last_page: 100, density: :light)
        result = described_class.new(user).impacts_for([light_book])

        expect(result[light_book.id]).to be < 0
      end
    end

    context "with no books on the reading list and completed backfill" do
      before do
        5.times do
          create(:book, :completed, user: user, first_page: 1, last_page: 300)
        end
      end

      it "computes impact relative to completed book backfill" do
        big_book = create(:book, user: user, first_page: 1, last_page: 600, density: :average)
        result = described_class.new(user).impacts_for([big_book])

        expect(result[big_book.id]).to be_a(Integer)
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

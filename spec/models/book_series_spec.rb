require "rails_helper"

RSpec.describe "Book series", type: :model do
  let(:user) { create(:user) }

  describe "#in_series?" do
    it "returns true when both series_name and series_position are set" do
      book = create(:book, user: user, series_name: "Lord of the Rings", series_position: 1)
      expect(book.in_series?).to be true
    end

    it "returns false when series_name is nil" do
      book = create(:book, user: user, series_name: nil, series_position: 1)
      expect(book.in_series?).to be false
    end

    it "returns false when series_position is nil" do
      book = create(:book, user: user, series_name: "Lord of the Rings", series_position: nil)
      expect(book.in_series?).to be false
    end
  end

  describe "#series_predecessor" do
    it "returns the previous book in the series" do
      book1 = create(:book, user: user, title: "Fellowship", series_name: "LOTR", series_position: 1)
      book2 = create(:book, user: user, title: "Two Towers", series_name: "LOTR", series_position: 2)

      expect(book2.series_predecessor).to eq(book1)
    end

    it "returns nil for the first book in a series" do
      book1 = create(:book, user: user, title: "Fellowship", series_name: "LOTR", series_position: 1)
      expect(book1.series_predecessor).to be_nil
    end

    it "returns nil for non-series books" do
      book = create(:book, user: user, series_name: nil, series_position: nil)
      expect(book.series_predecessor).to be_nil
    end

    it "scopes to the same user" do
      other_user = create(:user)
      create(:book, user: other_user, title: "Fellowship", series_name: "LOTR", series_position: 1)
      book2 = create(:book, user: user, title: "Two Towers", series_name: "LOTR", series_position: 2)

      expect(book2.series_predecessor).to be_nil
    end
  end

  describe ".in_series scope" do
    it "returns books in the named series ordered by position" do
      book3 = create(:book, user: user, title: "Return", series_name: "LOTR", series_position: 3)
      book1 = create(:book, user: user, title: "Fellowship", series_name: "LOTR", series_position: 1)
      book2 = create(:book, user: user, title: "Two Towers", series_name: "LOTR", series_position: 2)
      create(:book, user: user, title: "Other Book")

      expect(Book.in_series("LOTR")).to eq([book1, book2, book3])
    end
  end
end

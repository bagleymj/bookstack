require "rails_helper"

RSpec.describe "Book ownership" do
  let(:user) { create(:user) }

  describe "default value" do
    it "defaults owned to false for new books" do
      book = Book.new(user: user, title: "Test", first_page: 1, last_page: 200)
      expect(book.owned).to eq(false)
    end
  end

  describe "scopes" do
    let!(:owned_book) { create(:book, user: user, owned: true) }
    let!(:unowned_book) { create(:book, :unowned, user: user) }

    it ".owned returns only owned books" do
      expect(user.books.owned).to contain_exactly(owned_book)
    end

    it ".unowned returns only unowned books" do
      expect(user.books.unowned).to contain_exactly(unowned_book)
    end
  end

  describe "#mark_owned!" do
    it "sets owned to true" do
      book = create(:book, :unowned, user: user)
      expect { book.mark_owned! }.to change { book.reload.owned? }.from(false).to(true)
    end
  end

  describe "factory" do
    it "creates owned books by default" do
      book = create(:book, user: user)
      expect(book.owned?).to be true
    end

    it "creates unowned books with :unowned trait" do
      book = create(:book, :unowned, user: user)
      expect(book.owned?).to be false
    end
  end
end

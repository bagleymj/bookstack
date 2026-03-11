require "rails_helper"

RSpec.describe Book, type: :model do
  let(:user) { create(:user) }

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
  end
end

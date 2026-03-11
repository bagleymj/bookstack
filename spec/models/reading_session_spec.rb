require 'rails_helper'

RSpec.describe ReadingSession, type: :model do
  describe "validations" do
    describe "#end_page_greater_than_start_page" do
      let(:user) { create(:user, onboarding_completed_at: Time.current) }
      let(:book) { create(:book, :reading, user: user) }

      it "is invalid when end_page is less than start_page" do
        session = build(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 30)
        expect(session).not_to be_valid
        expect(session.errors[:end_page]).to include("must be greater than or equal to start page")
      end

      it "is valid when end_page equals start_page" do
        session = build(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 50)
        expect(session).to be_valid
      end

      it "is valid when end_page is greater than start_page" do
        session = build(:reading_session, :completed, user: user, book: book, start_page: 50, end_page: 75)
        expect(session).to be_valid
      end

      it "skips validation when end_page is nil" do
        session = build(:reading_session, :in_progress, user: user, book: book, start_page: 50)
        expect(session).to be_valid
      end
    end
  end
end

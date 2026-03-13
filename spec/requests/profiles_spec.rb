require "rails_helper"

RSpec.describe "Profiles", type: :request do
  let(:user) { create(:user, onboarding_completed_at: Time.current) }

  before { sign_in user }

  describe "POST /profile/reset_pace" do
    before do
      user.update!(
        reading_pace_type: "books_per_year",
        reading_pace_value: 50,
        reading_pace_set_on: 100.days.ago.to_date
      )
    end

    it "resets reading_pace_set_on to today" do
      post reset_pace_profile_path

      expect(user.reload.reading_pace_set_on).to eq(Date.current)
    end

    it "preserves pace type and value" do
      post reset_pace_profile_path

      user.reload
      expect(user.reading_pace_type).to eq("books_per_year")
      expect(user.reading_pace_value).to eq(50)
    end

    it "destroys queued auto-scheduled reading goals" do
      book = create(:book, user: user, status: :unread)
      create(:reading_goal, user: user, book: book, status: :queued, auto_scheduled: true, position: 1)

      expect {
        post reset_pace_profile_path
      }.to change { user.reading_goals.where(status: :queued, auto_scheduled: true).count }.by(-1)
    end

    it "does not destroy active reading goals" do
      book = create(:book, user: user, status: :reading)
      create(:reading_goal, user: user, book: book, status: :active, auto_scheduled: true, position: 1)

      expect {
        post reset_pace_profile_path
      }.not_to change { user.reading_goals.where(status: :active).count }
    end

    it "does not destroy non-auto-scheduled goals" do
      book = create(:book, user: user, status: :unread)
      create(:reading_goal, user: user, book: book, status: :queued, auto_scheduled: false, position: 1)

      expect {
        post reset_pace_profile_path
      }.not_to change { user.reading_goals.where(auto_scheduled: false).count }
    end

    it "redirects to profile with notice" do
      post reset_pace_profile_path

      expect(response).to redirect_to(profile_path)
      follow_redirect!
      expect(response.body).to include("Pace reset")
    end
  end
end

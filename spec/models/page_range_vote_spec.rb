require "rails_helper"

RSpec.describe PageRangeVote, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      vote = build(:page_range_vote)
      expect(vote).to be_valid
    end

    it "requires first_page" do
      vote = build(:page_range_vote, first_page: nil)
      expect(vote).not_to be_valid
    end

    it "requires last_page" do
      vote = build(:page_range_vote, last_page: nil)
      expect(vote).not_to be_valid
    end

    it "requires first_page to be positive" do
      vote = build(:page_range_vote, first_page: 0)
      expect(vote).not_to be_valid
    end

    it "requires last_page to be positive" do
      vote = build(:page_range_vote, last_page: 0)
      expect(vote).not_to be_valid
    end

    it "enforces one vote per user per edition" do
      existing = create(:page_range_vote)
      duplicate = build(:page_range_vote, edition: existing.edition, user: existing.user)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:edition_id]).to be_present
    end

    it "allows same user to vote on different editions" do
      user = create(:user)
      edition1 = create(:edition)
      edition2 = create(:edition)
      create(:page_range_vote, edition: edition1, user: user)
      vote2 = build(:page_range_vote, edition: edition2, user: user)
      expect(vote2).to be_valid
    end
  end

  describe "callbacks" do
    it "recalculates edition recommended range after save" do
      edition = create(:edition)
      user = create(:user)

      expect {
        create(:page_range_vote, edition: edition, user: user, first_page: 3, last_page: 250)
      }.to change { edition.reload.recommended_first_page }.from(nil).to(3)
        .and change { edition.reload.recommended_last_page }.from(nil).to(250)
    end

    it "recalculates edition recommended range after destroy" do
      edition = create(:edition)
      user1 = create(:user)
      user2 = create(:user)

      create(:page_range_vote, edition: edition, user: user1, first_page: 1, last_page: 300)
      vote2 = create(:page_range_vote, edition: edition, user: user2, first_page: 10, last_page: 250)

      vote2.destroy

      expect(edition.reload.recommended_first_page).to eq(1)
      expect(edition.reload.recommended_last_page).to eq(300)
    end
  end
end

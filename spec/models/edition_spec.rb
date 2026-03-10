require "rails_helper"

RSpec.describe Edition, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      edition = build(:edition)
      expect(edition).to be_valid
    end

    it "requires isbn" do
      edition = build(:edition, isbn: nil)
      expect(edition).not_to be_valid
      expect(edition.errors[:isbn]).to be_present
    end

    it "enforces isbn uniqueness" do
      create(:edition, isbn: "9780140449334")
      duplicate = build(:edition, isbn: "9780140449334")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:isbn]).to be_present
    end
  end

  describe "associations" do
    it "has many page_range_votes" do
      edition = create(:edition)
      user = create(:user)
      vote = create(:page_range_vote, edition: edition, user: user)
      expect(edition.page_range_votes).to include(vote)
    end

    it "destroys dependent page_range_votes" do
      edition = create(:edition)
      user = create(:user)
      create(:page_range_vote, edition: edition, user: user)
      expect { edition.destroy }.to change(PageRangeVote, :count).by(-1)
    end
  end

  describe "#recalculate_recommended_range!" do
    let(:edition) { create(:edition) }

    context "with no votes" do
      it "sets recommended range to nil" do
        edition.recalculate_recommended_range!

        expect(edition.recommended_first_page).to be_nil
        expect(edition.recommended_last_page).to be_nil
      end
    end

    context "with one vote" do
      it "uses the single vote's values" do
        create(:page_range_vote, edition: edition, first_page: 5, last_page: 290)

        edition.recalculate_recommended_range!

        expect(edition.recommended_first_page).to eq(5)
        expect(edition.recommended_last_page).to eq(290)
      end
    end

    context "with three votes (odd count)" do
      it "uses the median of each" do
        user1 = create(:user)
        user2 = create(:user)
        user3 = create(:user)

        create(:page_range_vote, edition: edition, user: user1, first_page: 1, last_page: 280)
        create(:page_range_vote, edition: edition, user: user2, first_page: 5, last_page: 290)
        create(:page_range_vote, edition: edition, user: user3, first_page: 10, last_page: 300)

        edition.recalculate_recommended_range!

        expect(edition.recommended_first_page).to eq(5)
        expect(edition.recommended_last_page).to eq(290)
      end
    end

    context "with even number of votes" do
      it "averages the two middle values" do
        user1 = create(:user)
        user2 = create(:user)

        create(:page_range_vote, edition: edition, user: user1, first_page: 1, last_page: 280)
        create(:page_range_vote, edition: edition, user: user2, first_page: 5, last_page: 300)

        edition.recalculate_recommended_range!

        expect(edition.recommended_first_page).to eq(3)
        expect(edition.recommended_last_page).to eq(290)
      end
    end
  end
end

require "rails_helper"

RSpec.describe EditionCacheService do
  subject(:service) { described_class.new }

  describe "#overlay_local_data" do
    it "merges local edition data for matching ISBNs" do
      edition = create(:edition, isbn: "9780140449334", recommended_first_page: 5, recommended_last_page: 240)

      editions = [
        { isbn: "9780140449334", title: "Meditations", pages: 256 },
        { isbn: "9780199573202", title: "Meditations", pages: 192 }
      ]

      result = service.overlay_local_data(editions)

      matched = result.find { |e| e[:isbn] == "9780140449334" }
      expect(matched[:recommended_first_page]).to eq(5)
      expect(matched[:recommended_last_page]).to eq(240)
      expect(matched[:has_local_data]).to be true

      unmatched = result.find { |e| e[:isbn] == "9780199573202" }
      expect(unmatched[:has_local_data]).to be false
    end

    it "returns editions unchanged when no ISBNs present" do
      editions = [{ title: "No ISBN", pages: 100 }]

      result = service.overlay_local_data(editions)

      expect(result).to eq(editions)
    end

    it "returns editions unchanged when no local matches" do
      editions = [{ isbn: "9999999999999", title: "Unknown", pages: 100 }]

      result = service.overlay_local_data(editions)

      expect(result.first[:has_local_data]).to be false
    end
  end

  describe "#record_page_range" do
    let(:user) { create(:user) }

    it "creates an Edition and PageRangeVote" do
      expect {
        service.record_page_range(
          user: user,
          isbn: "9780140449334",
          first_page: 1,
          last_page: 256,
          metadata: { title: "Meditations", author: "Marcus Aurelius", page_count: 256 }
        )
      }.to change(Edition, :count).by(1)
        .and change(PageRangeVote, :count).by(1)

      edition = Edition.find_by(isbn: "9780140449334")
      expect(edition.title).to eq("Meditations")
      expect(edition.author).to eq("Marcus Aurelius")
      expect(edition.page_count).to eq(256)

      vote = PageRangeVote.find_by(edition: edition, user: user)
      expect(vote.first_page).to eq(1)
      expect(vote.last_page).to eq(256)
    end

    it "updates existing vote on re-record" do
      service.record_page_range(user: user, isbn: "9780140449334", first_page: 1, last_page: 256)

      expect {
        service.record_page_range(user: user, isbn: "9780140449334", first_page: 5, last_page: 240)
      }.to change(PageRangeVote, :count).by(0)

      vote = PageRangeVote.find_by(edition: Edition.find_by(isbn: "9780140449334"), user: user)
      expect(vote.first_page).to eq(5)
      expect(vote.last_page).to eq(240)
    end

    it "updates Edition metadata on re-record" do
      service.record_page_range(user: user, isbn: "9780140449334", first_page: 1, last_page: 256, metadata: { title: "Old" })
      service.record_page_range(user: user, isbn: "9780140449334", first_page: 1, last_page: 256, metadata: { title: "New" })

      expect(Edition.find_by(isbn: "9780140449334").title).to eq("New")
    end

    it "does nothing when isbn is blank" do
      expect {
        service.record_page_range(user: user, isbn: "", first_page: 1, last_page: 256)
      }.not_to change(Edition, :count)
    end

    it "does nothing when first_page or last_page is blank" do
      expect {
        service.record_page_range(user: user, isbn: "9780140449334", first_page: nil, last_page: 256)
      }.not_to change(Edition, :count)

      expect {
        service.record_page_range(user: user, isbn: "9780140449334", first_page: 1, last_page: nil)
      }.not_to change(Edition, :count)
    end

    it "triggers recommended range recalculation via callback" do
      service.record_page_range(user: user, isbn: "9780140449334", first_page: 5, last_page: 240)

      edition = Edition.find_by(isbn: "9780140449334")
      expect(edition.recommended_first_page).to eq(5)
      expect(edition.recommended_last_page).to eq(240)
    end
  end
end

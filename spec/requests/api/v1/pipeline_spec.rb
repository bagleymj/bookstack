require "rails_helper"

RSpec.describe "API V1 Pipeline", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) do
    create(:user,
      reading_pace_type: "books_per_year",
      reading_pace_value: 50,
      reading_pace_set_on: Date.current.beginning_of_year)
  end

  before { sign_in user }

  describe "GET /api/v1/pipeline" do
    it "returns heijunka metrics" do
      get "/api/v1/pipeline"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("heijunka")

      heijunka = body["heijunka"]
      expect(heijunka["pace_target"]).to eq(50)
      expect(heijunka["derived_target"]).to be_a(Integer)
      expect(heijunka).to have_key("pace_status")
      expect(heijunka).to have_key("deficit")
      expect(heijunka).to have_key("projected_completions")
      expect(heijunka).to have_key("queue_depth")
    end

    it "returns nil heijunka metrics when no pace is set" do
      user.update!(reading_pace_type: nil, reading_pace_value: nil)

      get "/api/v1/pipeline"

      body = JSON.parse(response.body)
      expect(body["heijunka"]["pace_status"]).to be_nil
      expect(body["heijunka"]["derived_target"]).to eq(0)
    end

    it "returns queue warning when books are insufficient" do
      book = create(:book, user: user, last_page: 300)
      create(:reading_goal, user: user, book: book, status: :queued,
             auto_scheduled: true, position: 1)

      get "/api/v1/pipeline"

      body = JSON.parse(response.body)
      expect(body["heijunka"]["queue_warning"]).to include("books")
    end
  end
end

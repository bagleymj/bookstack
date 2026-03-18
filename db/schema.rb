# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_03_18_001046) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "books", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "author"
    t.integer "total_pages", null: false
    t.integer "words_per_page", default: 250
    t.integer "current_page", default: 0
    t.integer "status", default: 0
    t.integer "density", default: 3
    t.float "actual_density_modifier"
    t.string "cover_image_url"
    t.string "isbn"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "first_page", default: 1, null: false
    t.integer "last_page", null: false
    t.datetime "completed_at"
    t.boolean "owned", default: false, null: false
    t.string "series_name"
    t.integer "series_position"
    t.index ["isbn"], name: "index_books_on_isbn"
    t.index ["user_id", "series_name"], name: "index_books_on_user_id_and_series_name", where: "(series_name IS NOT NULL)"
    t.index ["user_id", "status"], name: "index_books_on_user_id_and_status"
    t.index ["user_id"], name: "index_books_on_user_id"
  end

  create_table "daily_quotas", force: :cascade do |t|
    t.bigint "reading_goal_id", null: false
    t.date "date", null: false
    t.integer "target_pages", null: false
    t.integer "actual_pages", default: 0
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_daily_quotas_on_date"
    t.index ["reading_goal_id", "date"], name: "index_daily_quotas_on_reading_goal_id_and_date", unique: true
    t.index ["reading_goal_id"], name: "index_daily_quotas_on_reading_goal_id"
  end

  create_table "editions", force: :cascade do |t|
    t.string "isbn", null: false
    t.string "google_books_id"
    t.string "title"
    t.string "author"
    t.string "publisher"
    t.string "published_year"
    t.integer "page_count"
    t.string "cover_image_url"
    t.string "format"
    t.integer "recommended_first_page"
    t.integer "recommended_last_page"
    t.integer "page_range_votes_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["google_books_id"], name: "index_editions_on_google_books_id"
    t.index ["isbn"], name: "index_editions_on_isbn", unique: true
  end

  create_table "jwt_denylist", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.index ["jti"], name: "index_jwt_denylist_on_jti"
  end

  create_table "page_range_votes", force: :cascade do |t|
    t.bigint "edition_id", null: false
    t.bigint "user_id", null: false
    t.integer "first_page", null: false
    t.integer "last_page", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["edition_id", "user_id"], name: "index_page_range_votes_on_edition_id_and_user_id", unique: true
    t.index ["edition_id"], name: "index_page_range_votes_on_edition_id"
    t.index ["user_id"], name: "index_page_range_votes_on_user_id"
  end

  create_table "reading_goals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "book_id", null: false
    t.date "target_completion_date"
    t.date "started_on"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "discrepancy_acknowledged_on"
    t.integer "position"
    t.boolean "auto_scheduled", default: false, null: false
    t.index ["book_id"], name: "index_reading_goals_on_book_id"
    t.index ["user_id", "book_id"], name: "index_reading_goals_on_user_id_and_book_id"
    t.index ["user_id", "position"], name: "index_reading_goals_on_user_id_and_position"
    t.index ["user_id", "status"], name: "index_reading_goals_on_user_id_and_status"
    t.index ["user_id"], name: "index_reading_goals_on_user_id"
  end

  create_table "reading_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "book_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "start_page", null: false
    t.integer "end_page"
    t.integer "duration_seconds"
    t.integer "pages_read"
    t.float "words_per_minute"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "untracked", default: false, null: false
    t.integer "estimated_duration_seconds"
    t.float "wpm_snapshot"
    t.index ["book_id", "started_at"], name: "index_reading_sessions_on_book_id_and_started_at"
    t.index ["book_id"], name: "index_reading_sessions_on_book_id"
    t.index ["user_id", "started_at"], name: "index_reading_sessions_on_user_id_and_started_at"
    t.index ["user_id"], name: "index_reading_sessions_on_user_id"
  end

  create_table "user_reading_stats", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.float "average_wpm", default: 200.0
    t.integer "total_sessions", default: 0
    t.integer "total_pages_read", default: 0
    t.integer "total_reading_time_seconds", default: 0
    t.datetime "last_calculated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_reading_stats_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name"
    t.integer "default_words_per_page", default: 250
    t.integer "default_reading_speed_wpm", default: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_concurrent_books", default: 1, null: false
    t.integer "weekday_reading_minutes", default: 60, null: false
    t.integer "weekend_reading_minutes", default: 60, null: false
    t.datetime "onboarding_completed_at"
    t.string "reading_pace_type"
    t.integer "reading_pace_value"
    t.date "reading_pace_set_on"
    t.integer "weekend_mode", default: 1, null: false
    t.integer "concurrency_limit"
    t.date "quotas_generated_on"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "books", "users"
  add_foreign_key "daily_quotas", "reading_goals"
  add_foreign_key "page_range_votes", "editions"
  add_foreign_key "page_range_votes", "users"
  add_foreign_key "reading_goals", "books"
  add_foreign_key "reading_goals", "users"
  add_foreign_key "reading_sessions", "books"
  add_foreign_key "reading_sessions", "users"
  add_foreign_key "user_reading_stats", "users"
end

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

# ── DATABASE SAFETY GUARD ──────────────────────────────────────────
# Tests MUST be run through bin/rspec, which auto-backs-up the dev
# database first. This has been wiped 5 times by rspec boot-time
# operations (maintain_test_schema!, schema loads, etc.).
#
# Set BOOKSTACK_RSPEC_BACKUP_DONE=1 to bypass (e.g. CI environments).
unless ENV['BOOKSTACK_RSPEC_BACKUP_DONE'] == '1'
  abort <<~MSG

    BLOCKED: rspec must be run through bin/rspec to ensure a dev database
    backup is taken first.

    Run instead:  bin/rspec #{ARGV.join(' ')}

    This safeguard exists because the dev database has been wiped FIVE
    times by test-related operations. bin/rspec auto-backs-up before running.

  MSG
end

# ── maintain_test_schema! REMOVED ──────────────────────────────────
# This was the root cause of dev database wipes. It detects schema
# mismatches and runs db:test:load_schema, which has repeatedly
# corrupted the dev database. Manage test schema explicitly instead:
#
#   bin/safe_db migrate   (migrates dev DB, test follows automatically)
#
# If tests fail with "table doesn't exist" or similar, run:
#
#   BOOKSTACK_DB_BACKUP_DONE=1 RAILS_ENV=test bin/rails db:schema:load

require 'rspec/rails'
require 'webmock/rspec'
# Add additional requires below this line. Rails is not loaded until this point!

# Allow localhost connections (for Capybara/system tests) but block all external HTTP
WebMock.disable_net_connect!(allow_localhost: true)

Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/7-1/rspec-rails
  #
  # You can also this infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  # config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end

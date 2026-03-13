# Clean up stale data that may persist in the test database outside of
# transactional fixtures (e.g. from interrupted test runs or environment
# mismatch issues).
RSpec.configure do |config|
  config.before(:suite) do
    PageRangeVote.delete_all
    Edition.delete_all
  end
end

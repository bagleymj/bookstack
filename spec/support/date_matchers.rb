RSpec::Matchers.define :be_monday do
  match { |date| date.monday? }
  failure_message { |date| "expected #{date} (#{date.strftime('%A')}) to be a Monday" }
end

RSpec::Matchers.define :be_sunday do
  match { |date| date.sunday? }
  failure_message { |date| "expected #{date} (#{date.strftime('%A')}) to be a Sunday" }
end

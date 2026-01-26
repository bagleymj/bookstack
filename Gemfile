source "https://rubygems.org"

ruby "~> 3.3.0"

# Rails
gem "rails", "~> 7.1.5"

# Database
gem "pg", "~> 1.5"

# Web server
gem "puma", ">= 5.0"

# Asset pipeline
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

# CSS
gem "tailwindcss-rails"

# Authentication
gem "devise", "~> 4.9"

# JSON APIs
gem "jbuilder"

# Windows timezone data
gem "tzinfo-data", platforms: %i[windows jruby]

# Performance
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

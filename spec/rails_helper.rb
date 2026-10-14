# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Dir[Rails.root.join("spec", "support", "**", "*.rb")].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ "#{::Rails.root}/spec/fixtures" ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # In production the Rails executor clears ExecutionContext after each
  # request and job. RSpec runs every example in one process, so clear it
  # here. ExecutionContext.set with a block also puts back a key that was
  # missing as nil, so a spec that set :controller would leak
  # "controller" => nil into every later error report.
  config.before { ActiveSupport::ExecutionContext.clear }
end

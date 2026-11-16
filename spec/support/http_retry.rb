# frozen_string_literal: true

# HttpFetcher retries a busy server or a dropped connection, and waits
# between the tries. Examples count the tries but do not wait.
RSpec.configure do |config|
  config.before do
    allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end
end

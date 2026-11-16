# frozen_string_literal: true

# Sets ENV keys for the length of the block and puts back the old values, so
# the code under test reads ENV the way it does in production ([], fetch, key?).
module EnvHelpers
  def with_env(values)
    saved = values.keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

RSpec.configure do |config|
  config.include EnvHelpers
end

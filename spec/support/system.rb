# frozen_string_literal: true

require "capybara/rspec"
require "capybara/cuprite"

# System specs run the page in headless Chrome, so the JavaScript runs too.
# Cuprite talks to Chrome over CDP and needs no chromedriver. It finds Chrome
# on its own; set BROWSER_PATH to use a different binary.
#
# The driver has its own name. `driven_by :cuprite` would register a new :cuprite
# driver with Rails' defaults, which drops these options: CI then waited only
# Ferrum's default 10 seconds for Chrome to start.
Capybara.register_driver(:wit_cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1280, 800 ],
    headless: ENV["HEADFUL"].blank?,
    process_timeout: 20,
    timeout: 10,
    # Containers and CI runners have no user namespace for the Chrome sandbox.
    browser_options: ENV["CI"] ? { "no-sandbox" => nil } : {}
  )
end

Capybara.default_max_wait_time = 2
Capybara.disable_animation = true
# Find icon buttons by their accessible name, the way a screen reader does.
Capybara.enable_aria_label = true
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :wit_cuprite
  end
end

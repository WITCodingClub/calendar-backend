# frozen_string_literal: true

require "rails_helper"

# The options in spec/support/system.rb reach Chrome. When `driven_by` named
# Rails' own :cuprite driver, Rails dropped them, and CI failed when Chrome
# took more than 10 seconds to start.
RSpec.describe "System spec driver", type: :system do
  it "uses the options from spec/support/system.rb" do
    visit "about:blank"

    expect(page.driver.browser.options.process_timeout).to eq(20)
    expect(page.evaluate_script("[window.innerWidth, window.innerHeight]")).to eq([ 1280, 800 ])
  end
end

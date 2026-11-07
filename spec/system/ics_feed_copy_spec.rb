# frozen_string_literal: true

require "rails_helper"

# Issue #695: the copy button on the ICS feed page tells a screen reader the
# result, and selects the URL when the copy fails.
RSpec.describe "ICS feed copy button", type: :system do
  let(:user) { create(:user, :with_processed_courses) }

  before do
    sign_in user
    visit dashboard_ics_feed_path
  end

  # Replaces the Clipboard API, so the spec does not depend on the
  # clipboard permission of headless Chrome.
  def stub_clipboard(succeeds:)
    page.execute_script(<<~JS, succeeds)
      const [succeeds] = arguments
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          writeText: (text) => {
            window.copiedText = text
            return succeeds ? Promise.resolve() : Promise.reject(new Error("denied"))
          }
        }
      })
    JS
  end

  it "copies the URL and announces it" do
    stub_clipboard(succeeds: true)

    click_button "Copy"

    expect(page).to have_button("Copied")
    expect(page).to have_css("[role='status']", text: "Copied to the clipboard.", visible: :all)
    expect(page.evaluate_script("window.copiedText")).to eq(find_field("Your personal ICS URL").value)
  end

  it "selects the URL and announces the failure when the copy fails" do
    stub_clipboard(succeeds: false)

    click_button "Copy"

    expect(page).to have_button("Copy failed")
    expect(page).to have_css("[role='status']", text: "Could not copy.", visible: :all)
    expect(page.evaluate_script("document.activeElement.id")).to eq("ics-url-field")
  end
end

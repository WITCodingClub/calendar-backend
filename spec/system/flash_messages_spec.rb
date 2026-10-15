# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Flash messages", type: :system do
  # Adds a message to the page. Stimulus connects the controller when the
  # element appears, the same as for a message the server renders.
  def add_message(id, timeout:)
    page.execute_script(<<~JS, id, timeout)
      const [id, timeout] = arguments
      document.getElementById("flash-messages").insertAdjacentHTML("beforeend", `
        <div id="${id}" role="status" class="pointer-events-auto" data-controller="flash-message"
             data-flash-message-timeout-value="${timeout}">
          <p>${id}</p>
          <button type="button" aria-label="Dismiss" data-action="click->flash-message#dismiss">x</button>
        </div>`)
    JS
  end

  # A message with the same short timeout. When it is gone, the timeout of a
  # message added at the same time has passed too.
  def wait_for_timeout
    add_message("clock", timeout: 300)
    expect(page).to have_no_css("#clock")
  end

  it "keeps an error on the sign-in page until the user closes it" do
    visit edit_user_password_path

    alert = find("#flash-messages [role='alert']", text: "password reset email")
    wait_for_timeout
    expect(alert).to be_visible

    alert.click_button("Dismiss")
    expect(page).to have_no_css("#flash-messages [role='alert']")
  end

  context "with a message added to the page" do
    before { visit new_user_session_path }

    it "closes a message with a timeout by itself" do
      add_message("notice", timeout: 300)

      expect(page).to have_css("#notice")
      expect(page).to have_no_css("#notice")
    end

    it "stops the timer while the pointer is on the message" do
      add_message("notice", timeout: 300)
      find("#notice").hover

      wait_for_timeout
      expect(page).to have_css("#notice")

      find("h1").hover
      expect(page).to have_no_css("#notice")
    end

    it "stops the timer while the focus is on the message" do
      add_message("notice", timeout: 300)
      page.execute_script("document.querySelector('#notice button').focus()")

      wait_for_timeout
      expect(page).to have_css("#notice")

      page.execute_script("document.activeElement.blur()")
      expect(page).to have_no_css("#notice")
    end

    it "keeps the timer stopped while the focus is on the message, after the pointer leaves" do
      add_message("notice", timeout: 300)
      find("#notice").hover
      page.execute_script("document.querySelector('#notice button').focus()")
      find("h1").hover

      wait_for_timeout
      expect(page).to have_css("#notice")
    end
  end

  context "when the dashboard is on a phone" do
    before do
      page.driver.resize(390, 844)
      sign_in create(:user, :with_processed_courses)
      visit dashboard_root_path
      add_message("notice", timeout: 0)
    end

    def rect(selector)
      page.evaluate_script("document.querySelector('#{selector}').getBoundingClientRect().toJSON()")
    end

    it "places the message below the top bar and above the bottom nav, full width" do
      message = rect("#notice")

      expect(message["top"]).to be >= rect("header")["bottom"]
      expect(message["bottom"]).to be <= rect("nav[aria-label=Main].fixed.bottom-0")["top"]
      expect(message["width"]).to be > 390 - 40
    end
  end
end

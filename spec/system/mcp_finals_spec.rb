# frozen_string_literal: true

require "rails_helper"

# The final exams MCP App (McpTools::FinalsApp) in a fake host
# (spec/support/mcp_app_host.rb), with a real tool result.
RSpec.describe "MCP finals app", type: :system do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  it "groups the exams of my_finals by day" do
    course = create(:course, term: term, subject: "COMP", course_number: 2000, title: "Algorithms")
    create(:enrollment, user: user, course: course)
    create(:final_exam, term: term, crn: course.crn, course: course, location: "WENTW 010")

    start_host(McpTools::FinalsApp)
    send_tool_result(tool_result(McpTools::MyFinals, user, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: "Final exams")
      expect(page).to have_css("#summary", text: "1 exam · Dec 17")
      expect(page).to have_css("h2", text: /thursday, dec 17/i)
      exam = find(".exam[data-crn='#{course.crn}']")
      expect(exam).to have_text("8:00 – 10:00 AM")
      expect(exam).to have_css("strong", text: "COMP 2000")
      expect(exam).to have_text("Algorithms")
      expect(exam).to have_text("WENTW 010")
    end

    wait_for_host_message("ui/notifications/size-changed")
  end

  it "says when the finals schedule is not published" do
    # Catalog::Freshness lists a term once it has sections.
    create(:course, term: term)
    start_host(McpTools::FinalsApp)
    send_tool_result(tool_result(McpTools::MyFinals, user, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css(".notes li", text: "not published yet")
      expect(page).to have_css(".status", text: "No final exams to show.")
      # The advisory names the finals schedule, the source of this tool, not Banner.
      expect(page).to have_css(".advisory", text: "finals schedule")
      expect(page).to have_no_css(".advisory", text: "Banner")
    end
  end
end

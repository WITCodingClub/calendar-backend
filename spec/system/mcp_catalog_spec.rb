# frozen_string_literal: true

require "rails_helper"

# The catalog MCP App (McpTools::CatalogApp) in a fake host
# (spec/support/mcp_app_host.rb), with a real tool result.
RSpec.describe "MCP catalog app", type: :system do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  it "draws a card for each section of search_sections" do
    open = create(:course, term: term, crn: 20145, subject: "COMP", course_number: 2350, title: "Data Structures",
                           seats_capacity: 30, seats_available: 12)
    create(:course_meeting_time, course: open, day_of_week: :monday, begin_time: 1000, end_time: 1140)
    create(:course_meeting_time, course: open, day_of_week: :wednesday, begin_time: 1000, end_time: 1140)
    create(:course, term: term, crn: 20311, subject: "COMP", course_number: 2400, seats_capacity: 30, seats_available: 0)

    start_host(McpTools::CatalogApp)
    send_tool_result(tool_result(McpTools::SearchSections, user, term_uid: term.uid, subject: [ "COMP" ]))

    within_frame("app") do
      expect(page).to have_css("h1", text: "Sections, #{term.name}")
      expect(page).to have_css("#summary", text: "Showing 1–2 of 2")
      card = find("article[data-crn='20145']")
      expect(card).to have_text("COMP 2350")
      expect(card).to have_text("12 of 30 open")
      # The two meetings have the same time, so they share one line.
      expect(card).to have_css(".meeting", count: 1, text: "Mon, Wed")
      expect(card).to have_css(".meeting", text: "10:00 – 11:40 AM")
      expect(find("article[data-crn='20311']")).to have_text("Full")
      expect(page).to have_css(".advisory", text: "program director")
    end

    wait_for_host_message("ui/notifications/size-changed")
  end

  it "draws one section of get_section as a card" do
    course = create(:course, term: term, crn: 20145, subject: "COMP", course_number: 2350, title: "Data Structures",
                             seats_capacity: 30, seats_available: 3)

    start_host(McpTools::CatalogApp)
    send_tool_result(tool_result(McpTools::GetSection, user, crn: course.crn, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: /COMP 2350-\w+, Data Structures/)
      card = find("article[data-crn='20145']")
      expect(card).to have_text("3 of 30 open")
      expect(card).to have_css(".seats.low")
    end
  end

  it "lists the sections of similar_sections" do
    course = create(:course, term: term, crn: 20145)

    start_host(McpTools::CatalogApp)
    send_tool_result(tool_result(McpTools::SimilarSections, user, crn: course.crn, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: "Sections like CRN 20145")
      expect(page).to have_css(".status", text: "No similar sections.")
    end
  end

  it "draws a course with its description and sections" do
    create(:catalog_course, :with_details, subject_code: "COMP", course_number: 2350, title: "Algorithms",
                                           description: "Sorting and graphs.")
    create(:course, term: term, crn: 20145, subject: "Computer Science (COMP)", course_number: 2350)

    start_host(McpTools::CatalogApp)
    send_tool_result(tool_result(McpTools::GetCourse, user, code: "COMP 2350", term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: "COMP 2350, Algorithms")
      expect(page).to have_css("#summary", text: "4 credits · Usually offered Fall, Spring")
      expect(page).to have_css(".description", text: "Sorting and graphs.")
      expect(page).to have_css("article[data-crn='20145']")
    end
  end

  it "draws an instructor with the tags and the sections" do
    faculty = create(:faculty)
    create(:teacher_rating_tag, faculty: faculty, tag_name: "Caring", tag_count: 3)
    create(:course, term: term, crn: 20145).faculties << faculty

    start_host(McpTools::CatalogApp)
    send_tool_result(tool_result(McpTools::GetInstructor, user, instructor_id: faculty.public_id, term_uid: term.uid))

    within_frame("app") do
      expect(page).to have_css("h1", text: faculty.full_name)
      expect(page).to have_css(".chip", text: "Caring 3")
      expect(page).to have_css("article[data-crn='20145']")
    end
  end

  it "shows the error text of a tool error" do
    start_host(McpTools::CatalogApp)
    send_tool_result(tool_result(McpTools::GetCourse, user, code: "COMP 9999"))

    within_frame("app") do
      expect(page).to have_css("[role='alert']", text: "No course COMP 9999")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Calls every MCP tool with realistic data and checks its structured result
# against the tool's output_schema, the same check an MCP client makes.
#
# The check is stricter than the published schema: an object that does not
# set additionalProperties takes no key that its schema does not name. So a
# new key in a serializer fails here until the schema names it, while
# clients still accept the new key.
RSpec.describe "MCP tool output schemas" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  # Term.current depends on the date.
  around { |example| travel_to(Time.zone.local(2026, 10, 22, 12)) { example.run } }

  # Each tool with its arguments. A Proc runs in the example.
  def call(tool, **arguments)
    tool.call(server_context: mcp_context(user), **arguments)
  end

  def strict(node)
    case node
    when Hash
      node = node.transform_values { |value| strict(value) }
      node = node.merge(additionalProperties: false) if node.key?(:properties) && !node.key?(:additionalProperties)
      node
    when Array then node.map { |value| strict(value) }
    else node
    end
  end

  def schema_errors(tool, result)
    schemer = JSONSchemer.schema(strict(tool.output_schema.to_h).deep_stringify_keys, format: true)
    # The client gets JSON, so check the JSON form: dates and times as strings.
    schemer.validate(JSON.parse(result.structured_content.to_json)).map { |error| error.fetch("error") }
  end

  def expect_valid(tool, **arguments)
    result = call(tool, **arguments)

    expect(result.error?).to be(false), "#{tool.name_value} failed: #{result.content.first&.dig(:text)}"
    expect(schema_errors(tool, result)).to be_empty, "#{tool.name_value}: #{schema_errors(tool, result).join("\n")}"
    result.structured_content
  end

  it "gives every tool an output schema" do
    expect(McpTools.all.reject(&:output_schema).map(&:name_value)).to be_empty
  end

  it "puts the advisory in the schema of each academic planning tool, and only there" do
    planning, other = McpTools.all.partition(&:academic_planning?)

    expect(planning.map { |tool| tool.output_schema.to_h[:required] }).to all(include("advisory"))
    expect(planning.map { |tool| tool.output_schema.to_h.dig(:properties, :advisory) }).to all(eq(McpTools::BaseTool::ADVISORY_SCHEMA))
    expect(other.map { |tool| tool.output_schema.to_h[:properties] }).to all(satisfy { |props| !props.key?(:advisory) })
  end

  it "finds a wrong type, a missing key, and a key that the schema does not name" do
    result = MCP::Tool::Response.new([], structured_content: { current_term_uid: "202620", terms: [], extra: 1 })

    expect(schema_errors(McpTools::ListTerms, result)).to contain_exactly(
      a_string_including("current_term_uid"), a_string_including("next_term_uid"), a_string_including("extra")
    )
  end

  context "with full data" do
    let(:term) do
      create(:term, year: 2026, season: :fall, start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 18),
                    sections_synced_at: 1.day.ago, details_synced_at: 2.days.ago)
    end
    let(:faculty) do
      create(:faculty, title: "Professor", department: "Computing", school: "Computing and Data Science", rmp_id: "VGVhY2hlci0x")
    end
    let(:lecture) do
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2350, title: "Data Structures",
                      credit_hours: 4, seats_capacity: 30, seats_available: 5, grade_mode: "Standard Letter",
                      is_section_linked: true, link_identifier: "A1", links_fetched_at: 1.day.ago)
    end
    let(:lab) do
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2350, section_number: "02",
                      schedule_type: :laboratory, title: "Data Structures Lab", link_identifier: "B1")
    end
    let(:meeting_time) { create(:course_meeting_time, course: lecture) }
    let(:friend) { create(:user) }

    before do
      Rails.cache.clear
      create(:rating_distribution, faculty: faculty, r1: 1, r2: 0, r3: 2, r4: 3, r5: 4, total: 10)
      create(:teacher_rating_tag, faculty: faculty, tag_name: "Clear grading", tag_count: 4)
      create(:rmp_rating, faculty: faculty, comment: "Clear lectures.", course_name: "COMP2350", clarity_rating: 5,
                          difficulty_rating: 3, would_take_again: true, rating_tags: "Clear grading--Tough tests",
                          rating_date: 1.month.ago)
      lecture.faculties << faculty
      create(:section_link, course: lecture, linked_course: lab, credit_hours: 0)
      create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room))
      create(:course_meeting_time, course: lecture, day_of_week: :wednesday)
      create(:course_meeting_time, course: lab, begin_time: 930, end_time: 1120, meeting_schedule_type: :laboratory)

      prerequisite = create(:catalog_course, subject_code: "COMP", course_number: 1050, title: "Computer Science I")
      catalog_course = create(
        :catalog_course, :with_details,
        subject_code:  "COMP", course_number: 2350, title: "Data Structures", source_term: term,
        prerequisites: {
          "type" => "and", "operands" => [
            { "type" => "course", "subject_code" => "COMP", "course_number" => 1050, "min_grade" => "C", "level" => "Undergraduate" },
            { "type" => "test", "name" => "WIT Math Assessment", "score" => nil }
          ]
        },
        corequisites:  [ { "subject_code" => "COMP", "course_number" => 2351 } ],
        restrictions:  [ { "heading" => "Must be enrolled in one of the following Levels", "values" => [ "Undergraduate" ] } ]
      )
      create(:course_prerequisite, catalog_course: create(:catalog_course, subject_code: "COMP", course_number: 3350),
                                   required_catalog_course: catalog_course)
      create(:course_prerequisite, catalog_course: catalog_course, required_catalog_course: prerequisite)

      create(:final_exam, term: term, course: lecture, crn: lecture.crn, location: "WENTW 010")
      create(:finals_schedule, term: term, status: :completed, processed_at: 1.week.ago)
      create(:university_calendar_event, term: term, category: "holiday", summary: "Thanksgiving", all_day: true,
                                         start_time: Time.zone.local(2026, 11, 26), end_time: Time.zone.local(2026, 11, 27),
                                         last_fetched_at: 3.days.ago)

      create(:enrollment, user: user, course: lecture)
      create(:enrollment, user: user, course: lab)
      create(:calendar_preference, user: user, title_template: "{{course_code}}", color_id: "5",
                                   reminder_settings: [ { "time" => "15", "type" => "minutes", "method" => "popup" } ])
      create(:event_preference, user: user, preferenceable: meeting_time, title_template: "{{title}} lecture")

      friendship = create(:friendship, :accepted, requester: user, addressee: friend)
      friendship.update_visibility_for!(friend, :availability_only)
      create(:enrollment, user: friend, course: lecture)
    end

    it "matches the catalog tools" do
      expect_valid(McpTools::ListTerms)
      expect_valid(McpTools::ListSubjects)
      expect_valid(McpTools::ListSubjects, term_uid: term.uid)

      sections = expect_valid(McpTools::SearchSections, q: "Data")[:sections]
      expect(sections.pluck(:crn)).to contain_exactly(lecture.crn, lab.crn)

      section = expect_valid(McpTools::GetSection, crn: lecture.crn)
      expect(section[:course]).to include(code: "COMP 2350")
      expect(section[:final_exam]).to be_present
      expect(section[:advisory][:data_sources].first[:terms]).to be_present

      expect_valid(McpTools::SearchCourses, q: "COMP")
      course = expect_valid(McpTools::GetCourse, code: "COMP 2350", term_uid: term.uid)
      expect(course[:unlocks]).to be_present
      expect(course[:sections]).to be_present

      schedule = expect_valid(McpTools::CheckSchedule, crns: [ lecture.crn, lab.crn, 99_999 ])
      expect(schedule[:conflicts]).to be_present
      expect(schedule[:not_found]).to eq([ 99_999 ])

      expect_valid(McpTools::SearchInstructors, q: faculty.last_name)
      instructor = expect_valid(McpTools::GetInstructor, instructor_id: faculty.public_id, term_uid: term.uid)
      expect(instructor[:rmp]).to be_present
      expect(instructor[:recent_reviews]).to be_present

      expect_valid(McpTools::SearchReviews, instructor_id: faculty.public_id)
      expect_valid(McpTools::UniversityEvents)
      expect_valid(McpTools::CatalogGraphql, query: "{ terms { uid name } }")
    end

    it "matches the similar tools" do
      give_embedding(lecture, 0.0)
      give_embedding(create(:course, term: term, subject: lecture.subject, course_number: 3350), 0.1)
      other = give_embedding(create(:faculty), 0.1).tap { |person| lab.faculties << person }
      give_embedding(faculty, 0.0)

      expect(expect_valid(McpTools::SimilarSections, crn: lecture.crn)[:sections]).to be_present
      expect(expect_valid(McpTools::SimilarInstructors, instructor_id: faculty.public_id)[:instructors].pluck(:pub_id)).to eq([ other.public_id ])
    end

    it "matches the schedule tools" do
      courses = expect_valid(McpTools::MyCourses)[:courses]
      expect(courses.flat_map { |c| c[:meeting_times] }.map { |mt| mt[:location][:building] }).to include(nil, be_present)

      expect(expect_valid(McpTools::MyCourseHistory)[:terms].first[:courses]).to be_present
      expect(expect_valid(McpTools::MyBusyTimes, start_date: "2026-10-26", end_date: "2026-11-01")[:busy]).to be_present
      expect(expect_valid(McpTools::MyFinals)[:finals]).to be_present
      expect(expect_valid(McpTools::ListFriends)[:friends]).to be_present
      expect_valid(McpTools::FriendBusyTimes, friend_id: friend.public_id, start_date: "2026-10-26", end_date: "2026-11-01")
    end

    # BusyBlocks splits a meeting that goes past midnight, so the first part
    # ends at "24:00".
    it "matches the busy times of a meeting that goes past midnight" do
      zone = ActiveSupport::TimeZone["America/New_York"]
      create(:friend_meeting, user: user, start_time: zone.local(2026, 10, 27, 23), end_time: zone.local(2026, 10, 28, 1))

      busy = expect_valid(McpTools::MyBusyTimes, start_date: "2026-10-27", end_date: "2026-10-28")[:busy]
      expect(busy).to include(include(start: "23:00", end: "24:00"))
    end

    it "matches the settings tools" do
      settings = expect_valid(McpTools::MyCalendarSettings)
      expect(settings[:levels]).to be_present
      expect(settings[:classes]).to be_present

      expect_valid(McpTools::PreviewTemplate, template: "{{course_code}} {{room}}", meeting_time_id: meeting_time.public_id)

      saved = expect_valid(McpTools::UpdateClassSettings, meeting_time_id: meeting_time.public_id, color: "sage",
                                                          reminders: [ { time: 10, type: "minutes", method: "email" } ])
      expect(saved[:result]).to eq(:saved)

      deleted = expect_valid(McpTools::UpdateClassSettings, meeting_time_id: meeting_time.public_id,
                                                            reset: McpTools::BaseWriteTool::SETTING_FIELDS)
      expect(deleted[:class_settings]).to be_nil

      expect_valid(McpTools::UpdateCalendarSettings, level: "lecture", visibility: "private")
      expect(expect_valid(McpTools::UpdateCalendarSettings, level: "lecture", reset: [ "visibility" ])[:settings]).to be_nil

      expect(expect_valid(McpTools::SetNotifications, disabled: true, duration_hours: 2)[:notifications_disabled_until]).to be_present
      expect_valid(McpTools::MyCalendarSettings)
      expect(expect_valid(McpTools::SetNotifications, disabled: false)[:notifications_disabled_until]).to be_nil
    end

    # McpTools::Confirmation: the client asks, and the student declines.
    it "matches the write tools when the student declines" do
      declined = lambda do |tool, **arguments|
        question = tool.call(server_context: mcp_modern_context(user), **arguments)
        context  = mcp_modern_context(user, input_responses: mcp_confirmation("decline"), request_state: question.request_state)
        result   = tool.call(server_context: context, **arguments)

        expect(schema_errors(tool, result)).to be_empty, "#{tool.name_value}: #{schema_errors(tool, result).join("\n")}"
        result.structured_content
      end

      expect(declined.call(McpTools::UpdateClassSettings, meeting_time_id: meeting_time.public_id, color: "sage"))
        .to include(result: :unchanged, not_changed: include(reason: "declined"))
      expect(declined.call(McpTools::UpdateCalendarSettings, level: "lecture", visibility: "private")).to include(result: :unchanged)
      expect(declined.call(McpTools::SetNotifications, disabled: true)).to include(notifications_disabled: false)
    end
  end

  context "with sparse data" do
    # A term that no sync has finished, so the advisory times are null.
    let(:term) { create(:term) }
    let(:bare) { create(:course, term: term, title: "Independent Study", schedule_type: :independent_study) }
    let(:cancelled) { create(:course, term: term, status: "cancelled") }

    before do
      Rails.cache.clear
      bare
      cancelled
    end

    it "matches when the section has no meetings, instructor, details, links, seats, or final" do
      section = expect_valid(McpTools::GetSection, crn: bare.crn, term_uid: term.uid)
      expect(section).to include(instructors: [], meeting_times: [], final_exam: nil, course: nil)
      expect(section[:advisory][:data_sources].first[:terms]).to all(include(last_refreshed_at: nil))

      expect_valid(McpTools::SearchSections, term_uid: term.uid, q: "nothing matches this")
      expect_valid(McpTools::SimilarSections, crn: bare.crn, term_uid: term.uid)

      schedule = expect_valid(McpTools::CheckSchedule, term_uid: term.uid, crns: [ cancelled.crn ])
      expect(schedule[:totals]).to include(earliest_start: nil, latest_end: nil)
    end

    it "matches a course with no details and an instructor with no ratings" do
      create(:catalog_course, subject_code: "MATH", course_number: 1750, title: nil)
      faculty = create(:faculty)
      bare.faculties << faculty

      course = expect_valid(McpTools::GetCourse, code: "MATH 1750")
      expect(course).to include(prerequisites: nil, description: nil, details_fetched_at: nil)

      expect_valid(McpTools::SearchCourses, q: "MATH")
      instructor = expect_valid(McpTools::GetInstructor, instructor_id: faculty.public_id)
      expect(instructor).to include(rmp: nil, rating_distribution: nil, recent_reviews: [])
      expect_valid(McpTools::SearchInstructors)
      expect_valid(McpTools::SimilarInstructors, instructor_id: faculty.public_id)
      expect_valid(McpTools::SearchReviews)
    end

    it "matches the user tools with no courses, friends, or settings" do
      expect(expect_valid(McpTools::MyCourses, term_uid: term.uid)[:courses]).to eq([])
      expect(expect_valid(McpTools::MyCourseHistory)[:terms]).to eq([])
      expect(expect_valid(McpTools::MyBusyTimes, start_date: "2026-10-26", end_date: "2026-10-26")[:busy]).to eq([])
      expect(expect_valid(McpTools::MyFinals, term_uid: term.uid)[:finals]).to eq([])
      expect(expect_valid(McpTools::ListFriends)[:friends]).to eq([])
      expect(expect_valid(McpTools::UniversityEvents)[:events]).to eq([])
      expect(expect_valid(McpTools::MyCalendarSettings)).to include(levels: [], classes: [], notifications_disabled_until: nil)
      expect(expect_valid(McpTools::ListTerms, active: true)).to include(next_term_uid: nil, terms: [])
    end

    it "matches a class with no professor, room, or settings" do
      meeting_time = create(:course_meeting_time, course: bare)
      create(:enrollment, user: user, course: bare)

      course = expect_valid(McpTools::MyCourses, term_uid: term.uid)[:courses].first
      expect(course[:professor]).to be_nil
      expect(expect_valid(McpTools::MyCourseHistory)[:terms].first[:courses]).to be_present

      expect_valid(McpTools::PreviewTemplate, template: "{{title}}", meeting_time_id: meeting_time.public_id)
      expect_valid(McpTools::UpdateClassSettings, meeting_time_id: meeting_time.public_id, title_template: "{{title}}")
      expect_valid(McpTools::UpdateCalendarSettings, level: "university:holiday", color: "tomato")
    end

    it "matches a GraphQL result with data and errors" do
      result = expect_valid(McpTools::CatalogGraphql, query: "{ section(crn: 1, termUid: 1) { crn } }")

      expect(result).to have_key("data")
    end
  end
end

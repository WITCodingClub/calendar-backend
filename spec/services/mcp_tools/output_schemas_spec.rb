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
                      is_section_linked: true, link_identifier: "A1", links_fetched_at: 1.day.ago,
                      waitlist_capacity: 10, waitlist_available: 8, part_of_term: "FA1", campus: "Boston",
                      cross_list_identifier: "01", cross_list_capacity: 40, cross_list_available: 12)
    end
    # The graduate section that meets with the lecture.
    let(:cross_listed) do
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 6350, title: "Graduate Algorithms",
                      cross_list_identifier: "01", cross_list_capacity: 40, cross_list_available: 12)
    end
    let(:lab) do
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2350, section_number: "02",
                      schedule_type: :laboratory, title: "Data Structures Lab", link_identifier: "B1")
    end
    let(:meeting_time) { create(:course_meeting_time, course: lecture) }
    let(:friend) { create(:user) }

    before do
      Rails.cache.clear
      cross_listed
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
        restrictions:  [ { "heading" => "Must be enrolled in one of the following Levels", "values" => [ "Undergraduate" ] } ],
        mutual_exclusions: [ { "subject_code" => "COMP", "course_number" => 6350, "level" => "Graduate", "min_grade" => nil } ],
        college: "School of Computing and Data Science", division: "Undergraduate", department: "Computer Science",
        levels: %w[Undergraduate Graduate], grading_modes: [ "Standard Letter" ],
        fees: [ { "level" => "Undergraduate", "description" => "Course materials", "amount_cents" => 9500 },
                { "level" => nil, "description" => nil, "amount_cents" => 1000 } ],
        learning_objectives: "Implement a hash table.\nAnalyze the runtime of a sort."
      )
      create(:catalog_course, subject_code: "COMP", course_number: 6350, title: "Graduate Algorithms")
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
      expect(section).to include(part_of_term: "FA1", campus: "Boston", waitlist: { capacity: 10, available: 8 },
                                 cross_list: { identifier: "01", crns: [ cross_listed.crn ], seats: { capacity: 40, available: 12 } })
      expect(section[:final_exam]).to be_present
      expect(section[:advisory][:data_sources].first[:terms]).to be_present

      expect_valid(McpTools::SearchCourses, q: "COMP")
      course = expect_valid(McpTools::GetCourse, code: "COMP 2350", term_uid: term.uid)
      expect(course[:unlocks]).to be_present
      expect(course).to include(college: "School of Computing and Data Science", levels: %w[Undergraduate Graduate],
                                learning_objectives: a_string_including("hash table"))
      expect(course[:fees].pluck("amount_cents")).to eq([ 9500, 1000 ])
      expect(course[:mutual_exclusions]).to contain_exactly(include("code" => "COMP 6350", "title" => "Graduate Algorithms", "linked" => true))
      expect(course[:sections]).to be_present

      schedule = expect_valid(McpTools::CheckSchedule, crns: [ lecture.crn, lab.crn, 99_999 ])
      expect(schedule[:conflicts]).to be_present
      expect(schedule[:not_found]).to eq([ 99_999 ])

      # COMP 2350's lecture and lab meet at the same time, so it has no schedule.
      Flipper.enable(FeatureFlags::SCHEDULE_BUILDER)
      create(:catalog_course, subject_code: "COMP", course_number: 9100)
      create(:course_meeting_time, course: cross_listed, day_of_week: :friday)
      options = expect_valid(McpTools::FindSchedules, term_uid: term.uid, courses: [ { codes: [ "COMP 6350" ] }, { codes: [ "COMP 9100" ] } ],
                                                      preferences: { avoid: [ { before: "10:00" } ], days: "fewer", breaks: "lunch" })
      expect(options[:schedules]).to be_present
      expect(options[:not_offered]).to eq([ "COMP 9100" ])
      relax = expect_valid(McpTools::FindSchedules, term_uid: term.uid, courses: [ { codes: [ "COMP 6350" ] } ],
                                                    preferences: { earliest: "18:00" })
      expect(relax[:relax]).to be_present

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

      create(:catalog_course, subject_code: "COMP", course_number: bare.course_number)
      Flipper.enable(FeatureFlags::SCHEDULE_BUILDER)
      options = expect_valid(McpTools::FindSchedules, term_uid: term.uid, courses: [ { codes: [ "COMP #{bare.course_number}" ] } ])
      expect(options[:schedules].first[:totals]).to include(earliest_start: nil, latest_end: nil)
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

  context "with term elective lists" do
    it "matches a list with courses, and one with no school, title, or text" do
      term = create(:term)
      list = create(:term_elective_list, term: term, body_text: "Any 2000-Level courses in COMP")
      catalog_course = create(:catalog_course)
      create(:term_elective_course, term_elective_list: list, subject_code: catalog_course.subject_code,
                                    course_number: catalog_course.course_number)
      TermElectiveCourse.link_catalog_courses
      create(:term_elective_course, term_elective_list: list, heading: nil)
      create(:term_elective_list, term: term, school: nil, title: nil, body_text: nil)

      result = expect_valid(McpTools::ListTermElectives, term_uid: term.uid)
      expect(result[:lists].size).to eq(2)
      expect(result[:advisory][:data_sources].first).to include(source: "Wentworth Registrar elective lists (PDF)")
    end
  end

  context "with degree programs", :degree_planning do
    let(:catalog_year) { create(:catalog_year, :imported, start_year: 2026) }
    let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }

    it "matches a program with plans and elective lists" do
      set = create(:requirement_set, degree_program: major, catalog_year: catalog_year, path: "/widgetry/widget-design-bs/")
      plan = create(:program_plan, requirement_set: set)
      group = create(:elective_group, requirement_set: set, program_plan: plan)
      create(:elective_group_course, elective_group: group, requires_approval: true)
      create(:program_plan_item, program_plan: plan, footnote: "1")
      create(:program_plan_item, :placeholder, program_plan: plan, elective_group: group, min_credits: nil, max_credits: nil)
      create(:program_plan_item, :choice, program_plan: plan, season: "summer")
      create(:degree_program, :concentration, slug: "widget-design-gears", parent_program: major)

      expect(expect_valid(McpTools::ListPrograms)[:programs].size).to eq(1)
      program = expect_valid(McpTools::GetDegreeRequirements, program: "widget-design-bs")
      expect(program[:plans].first[:terms].flat_map { |term| term[:items] }.pluck(:kind)).to eq(%w[course placeholder choice])
      expect(program[:advisory][:data_sources].first).to include(source: "Wentworth academic catalog (catalog.wit.edu)")
    end

    it "matches a minor with no plan, school, credits, or link" do
      minor = create(:degree_program, :minor, slug: "gear-minor", parent_program: nil)
      create(:requirement_set, degree_program: minor, catalog_year: catalog_year, school_name: nil, total_credits: nil)

      program = expect_valid(McpTools::GetDegreeRequirements, program: "gear-minor", catalog_year: "2026-2027")
      expect(program).to include(plans: [], elective_lists: [], school: nil, catalog_url: nil, description: nil)
      expect_valid(McpTools::ListPrograms, kind: "minor", q: "nothing matches this")
    end

    it "matches the program tools with active, planned, and ended programs" do
      create(:academic_profile, user: user, level: "Undergraduate", class_standing: "Junior", admit_term_uid: 202410,
                                leopardweb_synced_at: Time.current)
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)
      create(:student_program, :ended, user: user)
      minor = create(:degree_program, :minor, slug: "gear-minor", parent_program: nil)
      create(:requirement_set, degree_program: minor, catalog_year: catalog_year)

      programs = expect_valid(McpTools::MyPrograms)
      expect(programs).to include(class_standing: "Junior", admit_term: "Fall 2023")
      expect(programs[:ended_programs].size).to eq(1)

      added = expect_valid(McpTools::UpdateMyPlannedPrograms, action: "add", program: "gear-minor")
      expect(added).to include(result: "added", program: include(status: "planned", program: "gear-minor", catalog_term: nil))
      expect(expect_valid(McpTools::UpdateMyPlannedPrograms, action: "remove", program: "gear-minor")[:planned_programs]).to eq([])
    end

    it "matches the program tools with a planned pathway" do
      master = create(:degree_program, :master, slug: "widget-design-ms")
      pathway = create(:program_pathway, slug: "widget-design-4-plus-1")
      create(:program_pathway_step, program_pathway: pathway, degree_program: major, position: 1)
      create(:program_pathway_step, program_pathway: pathway, degree_program: master, position: 2, plan_years: nil)
      [ major, master ].each { |program| create(:requirement_set, degree_program: program, catalog_year: catalog_year) }

      added = expect_valid(McpTools::UpdateMyPlannedPrograms, action: "add", pathway: "widget-design-4-plus-1")
      expect(added[:pathway]).to include(id: "widget-design-4-plus-1")
      expect(expect_valid(McpTools::MyPrograms)[:planned_pathways].size).to eq(1)
      expect(expect_valid(McpTools::UpdateMyPlannedPrograms, action: "remove", pathway: "widget-design-4-plus-1")[:result]).to eq("removed")
    end

    it "matches the program tools with no profile or programs, and a declined change" do
      expect(expect_valid(McpTools::MyPrograms)).to include(level: nil, programs: [], message: McpTools::MyPrograms::NO_PROGRAMS_MESSAGE)

      create(:requirement_set, degree_program: major, catalog_year: catalog_year)
      question = McpTools::UpdateMyPlannedPrograms.call(server_context: mcp_modern_context(user), action: "add", program: "widget-design-bs")
      context = mcp_modern_context(user, input_responses: mcp_confirmation("decline"), request_state: question.request_state)
      result = McpTools::UpdateMyPlannedPrograms.call(server_context: context, action: "add", program: "widget-design-bs")

      expect(schema_errors(McpTools::UpdateMyPlannedPrograms, result)).to be_empty
      expect(result.structured_content).to include(result: "unchanged", program: nil, not_changed: include(reason: "declined"))
    end

    it "matches the degree progress of a plan with every row kind, and of a minor with lists" do
      term = create(:term, year: 2026, season: :fall)
      set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
      plan = create(:program_plan, requirement_set: set)
      group = create(:elective_group, requirement_set: set, program_plan: plan)
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3000)
      create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: 1000)
      create(:program_plan_item, :choice, program_plan: plan)
      create(:program_plan_item, :placeholder, program_plan: plan, elective_group: group)
      create(:program_plan_item, :placeholder, program_plan: plan, label: "Free Elective")
      create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 1000)
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)
      done = create(:course, term: term, subject: "WDGT", course_number: 1000, credit_hours: nil)
      create(:enrollment, user: user, course: done)
      create(:course_outcome, user: user, course: done)
      create(:enrollment, user: user, course: create(:course, term: term, subject: "WDGT", course_number: 3000))

      result = expect_valid(McpTools::MyDegreeProgress)
      expect(result[:programs].first[:requirements].pluck(:status)).to eq(%w[done open in_progress open])
      expect(result[:programs].first[:timeline]).to be_present

      minor = create(:degree_program, :minor, slug: "gear-minor", parent_program: nil)
      create(:elective_group, requirement_set: create(:requirement_set, degree_program: minor, catalog_year: catalog_year),
                              min_courses: nil, min_credits: 8)
      expect(expect_valid(McpTools::MyDegreeProgress, program: "gear-minor")[:programs].first[:requirements].first)
        .to include(kind: "elective_list", status: "open")
    end

    it "matches the HSS details of degree progress (#991)" do
      term = create(:term, year: 2026, season: :fall)
      set = create(:requirement_set, degree_program: major, catalog_year: catalog_year, hss_requirement: {
        "min_credits" => 24, "categories" => DegreeRequirements::HssNoteParser.base_categories + [
          { "name" => "Ethics", "subject_codes" => [], "courses" => %w[PHIL4501] },
          { "name" => "Writing intensive", "subject_codes" => [], "courses" => [] }
        ]
      })
      plan = create(:program_plan, requirement_set: set)
      hss = create(:elective_group, :subjects, requirement_set: set, subject_codes: DegreeRequirements::SharedElectives::HSS.subject_codes)
      english = create(:elective_group, requirement_set: set, name: "English Sequence")
      create(:elective_group_course, elective_group: english, subject_code: "ENGL", course_number: 1100)
      create(:program_plan_item, :placeholder, program_plan: plan, label: "English Sequence", elective_group: english)
      2.times { create(:program_plan_item, :placeholder, program_plan: plan, label: "HSS Elective", elective_group: hss) }
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202710)
      [ [ "ENGL", 1100 ], [ "HIST", 1000 ] ].each do |subject, number|
        create(:enrollment, user: user, course: create(:course, term: term, subject: subject, course_number: number))
      end

      hss_result = expect_valid(McpTools::MyDegreeProgress)[:programs].first[:hss]
      expect(hss_result[:categories].pluck(:hint)).to include(nil, { subject_codes: [], courses: [ "PHIL 4501" ] })
      expect(hss_result[:english][:courses]).to eq([ "ENGL 1100" ])
      expect(hss_result[:courses].pluck(:category)).to eq([ "Humanities" ])
      expect(hss_result[:open_slots]).to eq([ { label: "HSS Elective", planned_term: "Fall 2026", planned_term_uid: 202710,
                                                hss_category: "Social Sciences" } ])
    end

    it "matches the next term courses with a course, a choice, and an elective slot" do
      past = create(:term, uid: 202610, year: 2025, season: :fall, end_date: Date.new(2025, 12, 20))
      spring = create(:term, uid: 202720, year: 2027, season: :spring)
      set = create(:requirement_set, degree_program: major, catalog_year: catalog_year)
      plan = create(:program_plan, requirement_set: set)
      create(:program_plan_item, program_plan: plan, year_index: 1, season: "fall", subject_code: "WDGT", course_number: 1000)
      create(:program_plan_item, program_plan: plan, year_index: 1, season: "spring", subject_code: "WDGT", course_number: 2000)
      create(:program_plan_item, :choice, program_plan: plan, year_index: 1, season: "spring")
      create(:program_plan_item, :placeholder, program_plan: plan, year_index: 1, season: "spring", label: "Free Elective",
                                               elective_group: create(:elective_group, :any_course, requirement_set: set))
      create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 2000,
                              prerequisites: { "type" => "course", "subject_code" => "WDGT", "course_number" => 1000 })
      create(:course, term: spring, subject: "WDGT", course_number: 2000)
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202710)
      create(:enrollment, user: user, course: create(:course, term: past, subject: "WDGT", course_number: 1000))

      result = expect_valid(McpTools::MyNextTermCourses, term: "Spring 2027")

      expect(result[:programs].first[:planned].first[:courses].first).to include(code: "WDGT 2000", offered: true,
                                                                                 prerequisites: "met")
    end
  end
end

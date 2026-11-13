# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/catalog/schedule_options", :schedule_builder, type: :request do
  let(:term) { create(:term, uid: 202720) }

  def section(crn, code, schedule_type: "LEC", **attributes)
    subject_code, number = code.split
    CatalogCourse.find_or_create_by!(subject_code: subject_code, course_number: number.to_i)
    create(:course, term: term, crn: crn, subject: "Subject (#{subject_code})", course_number: number.to_i,
                    schedule_type: schedule_type, **attributes)
  end

  def meets(course, days, from, to)
    Array(days).each { |day| create(:course_meeting_time, course: course, day_of_week: day, begin_time: from, end_time: to) }
    course
  end

  def linked(lecture, lab)
    [ lecture, lab ].each { |course| course.update!(is_section_linked: true, links_fetched_at: Time.current) }
    create(:section_link, course: lecture, linked_course: lab, credit_hours: 0)
    create(:section_link, course: lab, linked_course: lecture, credit_hours: 4)
  end

  def post_options(body, path: "/api/v1/catalog/schedule_options", headers: {})
    post path, params: body, as: :json, headers: headers
  end

  let(:body) do
    {
      term_uid:    term.uid,
      courses:     [ { codes: [ "COMP 3350" ] }, { codes: [ "MATH 2300", "MATH 2860" ] } ],
      preferences: { day_off: "any", days: "fewer", breaks: "lunch", earliest: "09:00" },
      limit:       6
    }
  end

  before do
    lecture = meets(section(20410, "COMP 3350", credit_hours: 4), %i[monday wednesday], 1000, 1115)
    linked(lecture, meets(section(20411, "COMP 3350", schedule_type: "LAB", credit_hours: nil), :tuesday, 1300, 1450))
    meets(section(20520, "MATH 2300", credit_hours: 4), %i[monday wednesday], 1300, 1415)
    meets(section(20610, "MATH 2860", credit_hours: 4), %i[tuesday thursday], 900, 950)
  end

  it "builds and ranks schedules without a token" do
    post_options(body)

    expect(response).to have_http_status(:ok)
    data = response.parsed_body["data"]
    expect(data).to include("term" => { "uid" => 202720, "name" => term.name }, "count" => 2, "capped" => false,
                            "relax" => [], "not_offered" => [])
    best = data["schedules"].first
    expect(best).to include("rank" => 1, "crns" => %w[20410 20411 20520], "avoid_hits" => 0,
                            "courses" => [ { "code" => "COMP 3350", "crns" => %w[20410 20411] },
                                           { "code" => "MATH 2300", "crns" => %w[20520] } ])
    expect(best["highlights"]).to include("Thursdays and Fridays off", "Lunch break every day")
    expect(best["totals"]).to eq("credit_hours" => 8, "days" => %w[monday tuesday wednesday],
                                 "earliest_start" => "10:00", "latest_end" => "14:50", "meetings_before_nine" => 0)
    expect(response.headers["Cache-Control"]).not_to include("public")
  end

  it "counts the schedules on the count route" do
    post_options(body, path: "/api/v1/catalog/schedule_options/count")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("data" => { "count" => 2, "capped" => false })
  end

  it "lists the preferences to drop when no schedule fits" do
    post_options(body.merge(preferences: { day_off: [ "monday" ], latest: "15:00" }))

    data = response.parsed_body["data"]
    expect(data).to include("count" => 0, "schedules" => [])
    expect(data["relax"]).to eq([ { "preference" => "day_off", "label" => "Allow classes on Monday", "count" => 2 } ])
  end

  it "answers 400 INVALID_FILTER for an unknown course, term, or preference" do
    [
      body.merge(courses: [ { codes: [ "ZZZZ 9999" ] } ]),
      body.merge(term_uid: 1),
      body.merge(preferences: { weekends: true }),
      body.merge(preferences: { breaks: "long" }),
      body.except(:courses)
    ].each do |bad|
      post_options(bad)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("INVALID_FILTER")
    end
  end

  it "allows a POST from any origin" do
    process :options, "/api/v1/catalog/schedule_options/count",
            headers: { "Origin" => "https://example.com", "Access-Control-Request-Method" => "POST" }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    expect(response.headers["Access-Control-Allow-Methods"]).to include("POST")
  end

  it "lets a browser on another origin read Retry-After" do
    post_options(body, path: "/api/v1/catalog/schedule_options/count", headers: { "Origin" => "https://example.com" })

    expect(response.headers["Access-Control-Expose-Headers"]).to include("Retry-After")
  end

  # The term, the aliases, the catalog courses, the sections, and the fixed
  # levels of the preload: meetings, rooms, buildings, links, partners, and
  # the partners' links and meetings. Rails skips a level that it already
  # has, so the count can be lower, but it never grows with the courses.
  it "answers in a fixed number of queries, whatever the number of courses" do
    small = count_queries { post_options(body.merge(courses: [ { codes: [ "COMP 3350" ] } ])) }
    %w[PHIL ENGL HIST].each_with_index { |code, index| meets(section(20700 + index, "#{code} 2100"), :friday, 1000 + (index * 100), 1050 + (index * 100)) }
    large = count_queries do
      post_options(body.merge(courses: [ *body[:courses], { codes: [ "PHIL 2100" ] }, { codes: [ "ENGL 2100", "HIST 2100" ] } ]))
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "count")).to eq(2)
    expect([ small, large ]).to all(be <= 14)
  end

  describe "the schedule_builder flag" do
    before { Flipper.disable(FeatureFlags::SCHEDULE_BUILDER) }

    it "answers 404 on both routes while the flag is off" do
      [ "/api/v1/catalog/schedule_options", "/api/v1/catalog/schedule_options/count" ].each do |path|
        post_options(body, path: path)

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("error" => "The schedule builder is not enabled", "code" => "NOT_FOUND")
      end
    end

    it "answers on both routes for a user with the flag, by the token" do
      user = create(:user)
      Flipper.enable_actor(FeatureFlags::SCHEDULE_BUILDER, user)

      [ "/api/v1/catalog/schedule_options", "/api/v1/catalog/schedule_options/count" ].each do |path|
        post_options(body, path: path, headers: auth_headers_for(user))

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("data", "count")).to eq(2)
      end
    end

    it "answers 404 for a user with the flag when the session was revoked or expired" do
      user = create(:user)
      Flipper.enable_actor(FeatureFlags::SCHEDULE_BUILDER, user)

      [ { revoked_at: Time.current }, { expires_at: 1.minute.ago } ].each do |ended|
        headers = auth_headers_for(user)
        UserSession.where(user: user).update_all(ended)

        post_options(body, headers: headers)

        expect(response).to have_http_status(:not_found)
      end
    end

    it "takes no search slot while the flag is off" do
      allow(Catalog::ScheduleOptions::Slots::SEMAPHORE).to receive(:try_acquire).and_call_original

      post_options(body)

      expect(Catalog::ScheduleOptions::Slots::SEMAPHORE).not_to have_received(:try_acquire)
    end

    it "answers 404 for a user without the flag or with a bad token" do
      post_options(body, headers: auth_headers_for(create(:user)))
      expect(response).to have_http_status(:not_found)

      post_options(body, headers: { "Authorization" => "Bearer not-a-token" })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the search slots" do
    it "answers 503 with Retry-After when every slot is in use, and counts it" do
      allow(Catalog::ScheduleOptions::Slots::SEMAPHORE).to receive(:try_acquire).and_return(false)
      allow(Yabeda.calendar.schedule_builder_busy_total).to receive(:increment)

      [ "/api/v1/catalog/schedule_options", "/api/v1/catalog/schedule_options/count" ].each do |path|
        post_options(body, path: path)

        expect(response).to have_http_status(:service_unavailable)
        expect(response.headers["Retry-After"]).to eq("1")
        expect(response.parsed_body).to include("code" => "SCHEDULE_BUILDER_BUSY", "retry_after" => 1)
      end
      expect(Yabeda.calendar.schedule_builder_busy_total).to have_received(:increment).with({ surface: "api" }).twice
    end

    it "frees the slot when the search fails" do
      allow(Catalog::ScheduleOptions::Search).to receive(:new).and_raise(ArgumentError, "boom")

      post_options(body)

      expect(response).to have_http_status(:internal_server_error)
      expect(Catalog::ScheduleOptions::Slots::SEMAPHORE.available_permits).to eq(Catalog::ScheduleOptions::Slots::LIMIT)
    end

    it "frees the slot after an answer" do
      post_options(body)

      expect(Catalog::ScheduleOptions::Slots::SEMAPHORE.available_permits).to eq(Catalog::ScheduleOptions::Slots::LIMIT)
    end
  end
end

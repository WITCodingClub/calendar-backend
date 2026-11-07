# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseDataSyncJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:term) { create(:term, uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    create(:course,
           crn: 12345, term: term, title: "Data Structures", subject: "COMP",
           course_number: 2000, section_number: "1", schedule_type: "LEC",
           credit_hours: 4, grade_mode: "Standard Letter",
           start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15))
  end

  # Banner's getFacultyMeetingTimes shape, as Catalog::LeopardWebClient returns it.
  def banner_meeting_time(building: "IRAH", description: "Ira Allen Hall", room: "112")
    {
      "building"             => building,
      "building_description" => description,
      "room"                 => room,
      "startDate"            => "09/08/2026",
      "endDate"              => "12/15/2026",
      "startTime"            => "1300",
      "endTime"              => "1445",
      "days"                 => { "monday" => true, "wednesday" => true }
    }
  end

  def banner_faculty(name: "Elijah Sanderson", email: "sandersone1@wit.edu")
    { "displayName" => name, "emailAddress" => email, "primaryIndicator" => true }
  end

  def class_details(meeting_times:, faculty: [])
    {
      title: "Data Structures",
      subject: "COMP",
      section_number: "01",
      schedule_type: "Lecture (LEC)",
      credit_hours: 4,
      grade_mode: "Standard Letter",
      seats_available: 5,
      seats_capacity: 30,
      waitlist_available: 1,
      waitlist_capacity: 5,
      meeting_times: meeting_times,
      faculty: faculty
    }
  end

  def stub_leopard_web(meeting_times, faculty: [])
    allow(Catalog::LeopardWebClient).to receive(:get_active_terms)
      .and_return({ success: true, terms: [ { code: term.uid.to_s, description: term.name } ] })
    allow(Catalog::LeopardWebClient).to receive(:get_class_details)
      .with(term: term.uid, course_reference_number: course.crn)
      .and_return(class_details(meeting_times: meeting_times, faculty: faculty))
  end

  def linked_rooms
    course.meeting_times.reload.flat_map { |mt| mt.rooms.map { |r| [ r.building.abbreviation, r.number ] } }.uniq
  end

  before do
    Catalog::MeetingTimesIngest.call(
      course: course,
      raw_meeting_times: Catalog::MeetingTimesIngest.normalize_leopard_web([ banner_meeting_time ])
    )
  end

  it "enqueues the course details sync for each term it syncs" do
    stub_leopard_web([ banner_meeting_time(room: "308") ])

    expect { described_class.perform_now(term_uids: [ term.uid ]) }
      .to have_enqueued_job(Catalog::CourseDetailsSyncJob).with(term.uid)
  end

  describe "details batch" do
    before { stub_leopard_web([ banner_meeting_time(room: "308") ]) }

    it "puts the details jobs in one batch, which waits for them" do
      # The :test adapter gives a job no batch, so the details job goes to the
      # Solid Queue tables here, as in production.
      previous = Catalog::CourseDetailsSyncJob.queue_adapter
      Catalog::CourseDetailsSyncJob.queue_adapter = :solid_queue
      described_class.perform_now(term_uids: [ term.uid ])

      batch = SolidQueue::Batch.last
      expect(batch.metadata[:term_uids]).to eq([ term.uid ])
      expect(batch.jobs.pluck(:class_name)).to eq([ "Catalog::CourseDetailsSyncJob" ])
      expect(batch).not_to be_finished
      expect(SolidQueue::Job.where(class_name: "Embeddings::BackfillJob")).to be_empty
    ensure
      Catalog::CourseDetailsSyncJob.queue_adapter = previous
    end

    it "starts the embeddings backfill when the batch finishes" do
      described_class.perform_now(term_uids: [ term.uid ])

      # The :test adapter does not run the details job, so the batch has no
      # Solid Queue jobs and finishes at once. Its callback always goes
      # through Solid Queue.
      expect(SolidQueue::Job.where(class_name: "Embeddings::BackfillJob").count).to eq(1)
    end
  end

  it "writes the new room when the registrar moves the section" do
    stub_leopard_web([ banner_meeting_time(room: "308") ])

    described_class.perform_now

    expect(linked_rooms).to eq([ [ "IRAH", "308" ] ])
  end

  it "writes the new building when the registrar moves the section" do
    stub_leopard_web([ banner_meeting_time(building: "BEAT", description: "Beatty Hall", room: "410") ])

    described_class.perform_now

    expect(linked_rooms).to eq([ [ "BEAT", "410" ] ])
  end

  it "clears the room when Banner no longer reports one" do
    stub_leopard_web([ banner_meeting_time(building: nil, description: nil, room: nil) ])

    described_class.perform_now

    expect(linked_rooms).to eq([ [ "TBD", "0" ] ])
  end

  it "reuses the meeting time rows so tracked calendar events stay attached" do
    ids_before = course.meeting_times.pluck(:id).sort
    stub_leopard_web([ banner_meeting_time(room: "308") ])

    described_class.perform_now

    expect(course.meeting_times.reload.pluck(:id).sort).to eq(ids_before)
  end

  # Courses::Processor serves a section from the catalog when this is recent.
  it "records when Banner confirmed the section, even when nothing changed" do
    stub_leopard_web([ banner_meeting_time ])

    freeze_time do
      described_class.perform_now

      expect(course.reload.banner_synced_at).to eq(Time.current)
    end
  end

  # Catalog::Freshness reports this time in the MCP advisory.
  it "records when the run for the term finished" do
    stub_leopard_web([ banner_meeting_time ])

    freeze_time do
      described_class.perform_now(term_uids: [ term.uid ])

      expect(term.reload.sections_synced_at).to eq(Time.current)
    end
  end

  it "leaves the confirmation time alone when Banner returns nothing for the section" do
    stub_leopard_web([])
    allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(nil)

    described_class.perform_now

    expect(course.reload.banner_synced_at).to be_nil
  end

  it "keeps the stored meeting times when Banner returns none" do
    stub_leopard_web([])

    described_class.perform_now

    expect(course.meeting_times.reload.count).to eq(2)
    expect(linked_rooms).to eq([ [ "IRAH", "112" ] ])
  end

  it "writes the seat and waitlist counts" do
    stub_leopard_web([ banner_meeting_time ])

    described_class.perform_now

    expect(course.reload).to have_attributes(seats_capacity: 30, seats_available: 5, waitlist_capacity: 5, waitlist_available: 1)
  end

  describe "credit hours" do
    # getClassDetails gives the course's credits, so it says 4 for a lab.
    it "keeps the section's own credit hours from the import" do
      course.update!(schedule_type: "LAB", credit_hours: nil)
      stub_leopard_web([ banner_meeting_time ])

      described_class.perform_now

      expect(course.reload.credit_hours).to be_nil
    end
  end

  describe "section links" do
    it "fetches Banner's pairs for a linked section" do
      course.update!(is_section_linked: true, link_identifier: "A1")
      stub_leopard_web([ banner_meeting_time ])
      allow(Catalog::SectionLinksSync).to receive(:call)

      described_class.perform_now

      expect(Catalog::SectionLinksSync).to have_received(:call).with(course)
    end

    it "sends no link request for a section that is not linked" do
      stub_leopard_web([ banner_meeting_time ])
      allow(Catalog::SectionLinksSync).to receive(:call)

      described_class.perform_now

      expect(Catalog::SectionLinksSync).not_to have_received(:call)
    end
  end

  describe "term selection" do
    it "syncs the running and upcoming terms, not every term Banner lists" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_raise("Banner should not be asked")
      allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(nil)
      job = described_class.new

      expect(job.send(:default_term_uids)).to include(term.uid)
    end

    it "leaves out a term that has already ended" do
      old_term = create(:term, uid: 201710, season: :fall, year: 2016,
                        start_date: Date.new(2016, 9, 1), end_date: Date.new(2016, 12, 20))

      expect(described_class.new.send(:default_term_uids)).not_to include(old_term.uid)
    end

    # Term.current picks by calendar month, not by whether classes are still
    # running, so it advances to the next term before the current one ends.
    # Term.current_and_future alone drops a still-running term twice a year.
    # These two cases are why default_term_uids unions in Term.active.
    context "when a running term overlaps the next one" do
      let!(:summer_2026) do
        create(:term, uid: 202630, season: :summer, year: 2026,
               start_date: Date.new(2026, 5, 18), end_date: Date.new(2026, 8, 20))
      end
      # The outer term is Fall 2026 (202710); it just needs real dates here.
      let!(:fall_2026) do
        term.tap { |t| t.update!(start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 20)) }
      end
      let!(:spring_2027) do
        create(:term, uid: 202720, season: :spring, year: 2027,
               start_date: Date.new(2027, 1, 12), end_date: Date.new(2027, 5, 5))
      end

      it "keeps the fall term in December, after the heuristic jumps to spring" do
        travel_to(Date.new(2026, 12, 18)) do
          expect(Term.current_and_future.pluck(:uid)).not_to include(fall_2026.uid)
          expect(described_class.new.send(:default_term_uids)).to include(fall_2026.uid)
        end
      end

      it "keeps the summer term in August, while it is still in session" do
        travel_to(Date.new(2026, 8, 1)) do
          expect(Term.current_and_future.pluck(:uid)).not_to include(summer_2026.uid)
          expect(described_class.new.send(:default_term_uids)).to include(summer_2026.uid)
        end
      end
    end
  end

  describe "concurrency key" do
    it "accepts the job arguments so a scoped run can be enqueued" do
      expect { described_class.new(term_uids: [ 202710 ]).concurrency_key }.not_to raise_error
    end

    it "stays a single key regardless of the arguments" do
      expect(described_class.new(term_uids: [ 202710 ]).concurrency_key)
        .to eq(described_class.new.concurrency_key)
    end
  end

  context "when a student with a Google calendar is enrolled" do
    let(:user)       { create(:user) }
    let(:credential) { create(:oauth_credential, user: user) }
    # A user counts as having a calendar through this association, the same way
    # CourseCalendars::NightlySyncJob selects them.
    let!(:course_calendar) { create(:course_calendar, oauth_credential: credential) }
    let!(:enrollment) { create(:enrollment, user: user, course: course) }

    before { user.update!(calendar_needs_sync: false) }

    it "marks the calendar for resync after a room-only change" do
      stub_leopard_web([ banner_meeting_time(room: "308") ])

      described_class.perform_now

      expect(user.reload.calendar_needs_sync).to be(true)
    end

    it "leaves the calendar alone when nothing changed" do
      stub_leopard_web([ banner_meeting_time ])

      described_class.perform_now

      expect(user.reload.calendar_needs_sync).to be(false)
    end
  end

  describe "instructor changes" do
    let(:previous_instructor) { create(:faculty, email: "minevichi@wit.edu") }

    before { course.faculties << previous_instructor }

    it "replaces the instructor when the registrar reassigns the section" do
      stub_leopard_web([ banner_meeting_time ], faculty: [ banner_faculty ])

      described_class.perform_now

      expect(course.reload.faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
    end

    it "keeps the stored instructor when Banner reports none" do
      stub_leopard_web([ banner_meeting_time ], faculty: [])

      described_class.perform_now

      expect(course.reload.faculties.map(&:email)).to eq([ "minevichi@wit.edu" ])
    end
  end

  describe "sections Banner confirmed recently" do
    # A retry after a cooldown must not start again at the first section.
    it "skips a section confirmed within FRESH_FOR" do
      course.update_column(:banner_synced_at, 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      allow(Catalog::LeopardWebClient).to receive(:get_class_details)

      described_class.perform_now(term_uids: [ term.uid ])

      expect(Catalog::LeopardWebClient).not_to have_received(:get_class_details)
    end

    it "syncs a section confirmed before FRESH_FOR" do
      course.update_column(:banner_synced_at, 4.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      stub_leopard_web([ banner_meeting_time ])

      described_class.perform_now(term_uids: [ term.uid ])

      expect(Catalog::LeopardWebClient).to have_received(:get_class_details)
    end

    # A night that stops early must not leave the next night to start over in
    # the first term.
    it "syncs the sections confirmed longest ago first, across terms" do
      spring = create(:term, uid: 202720, season: :spring, year: 2027)
      never = create(:course, term: spring)
      course.update_column(:banner_synced_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
      calls = []
      allow(Catalog::LeopardWebClient).to receive(:get_class_details) do |term:, course_reference_number:|
        calls << [ term, course_reference_number ]
        nil
      end

      described_class.perform_now(term_uids: [ term.uid, spring.uid ])

      expect(calls).to eq([ [ spring.uid, never.crn ], [ term.uid, course.crn ] ])
    end

    it "records the run for the term when every section is already fresh" do
      course.update_column(:banner_synced_at, 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

      freeze_time do
        described_class.perform_now(term_uids: [ term.uid ])

        expect(term.reload.sections_synced_at).to eq(Time.current)
      end
    end

    it "continues after the sections a cooldown attempt already synced" do
      first = course
      second = create(:course, term: term)
      calls = []
      allow(Catalog::LeopardWebClient).to receive(:get_class_details) do |course_reference_number:, **|
        calls << course_reference_number
        raise Catalog::BannerThrottle::CooldownError.new(60) if course_reference_number == second.crn && calls.count(second.crn) == 1

        class_details(meeting_times: [ banner_meeting_time ])
      end

      # The first run stops on the cooldown. The second stands in for the retry.
      2.times { described_class.perform_now(term_uids: [ term.uid ]) }

      expect(calls.count(first.crn)).to eq(1)
      expect(calls.count(second.crn)).to eq(2)
    end
  end

  describe "when Banner cools down" do
    it "stops the run, reports nothing, and tries again after the cooldown" do
      course
      allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_raise(Catalog::BannerThrottle::CooldownError.new(60))

      reports = capture_error_reports do
        expect { described_class.perform_now(term_uids: [ term.uid ]) }.to have_enqueued_job(described_class)
      end

      expect(reports).to be_empty
      expect(term.reload.sections_synced_at).to be_nil
    end

    context "with a retry" do
      before do
        course
        allow(Catalog::LeopardWebClient).to receive(:get_class_details)
          .and_raise(Catalog::BannerThrottle::CooldownError.new(60))
      end

      def job_started(ago, executions: 1)
        described_class.new(term_uids: [ term.uid ]).tap do |job|
          job.banner_first_attempt_at = ago.ago
          job.executions = executions
        end
      end

      it "keeps the time of the first attempt in the retry" do
        described_class.perform_now(term_uids: [ term.uid ])

        retry_data = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |job| job["job_class"] == described_class.name }
        first = Time.zone.parse(retry_data[Catalog::BannerCooldownRetry::FIRST_ATTEMPT_KEY])
        expect(first).to be_within(5.seconds).of(Time.current)
      end

      it "reads the time of the first attempt back from the job data" do
        first = 2.hours.ago.change(usec: 0)
        data = job_started(2.hours).tap { |job| job.banner_first_attempt_at = first }.serialize

        expect(described_class.new.tap { |job| job.deserialize(data) }.banner_first_attempt_at).to eq(first)
      end

      # Each cooldown used one of 10 attempts, so a run failed after about 35
      # minutes, and an admin retry that kept the count failed at once.
      it "tries again however many attempts it used, while the window lasts" do
        reports = capture_error_reports do
          expect { job_started(3.hours, executions: 40).perform_now }
            .to have_enqueued_job(described_class).at(a_value >= Catalog::BannerThrottle::COOLDOWN.from_now)
        end

        expect(reports).to be_empty
      end

      # A job in the queue at deploy has no first attempt time in its data.
      it "starts the window at the first attempt of a job queued without the time" do
        data = job_started(1.hour).serialize.except(Catalog::BannerCooldownRetry::FIRST_ATTEMPT_KEY)
        job = described_class.new.tap { |j| j.deserialize(data) }

        expect { job.perform_now }.to have_enqueued_job(described_class)
        expect(job.banner_first_attempt_at).to be_within(5.seconds).of(Time.current)
      end

      # SolidQueue::FailedExecution#retry sets executions to 0.
      it "starts a new window when Retry on the admin page started the job again" do
        job = job_started(5.hours, executions: 0)

        expect { job.perform_now }.to have_enqueued_job(described_class)
        expect(job.banner_first_attempt_at).to be_within(5.seconds).of(Time.current)
      end

      it "tries again when the retry starts exactly at the end of the window" do
        freeze_time do
          job = job_started(4.hours - Catalog::BannerCooldownRetry::WAIT)

          expect { job.perform_now }.to have_enqueued_job(described_class)
        end
      end

      it "stops at the end of the window and reports the cooldown as handled" do
        reports = capture_error_reports do
          expect { job_started(4.hours).perform_now }.not_to have_enqueued_job(described_class)
        end

        expect(reports.size).to eq(1)
        expect(reports.first.error).to be_a(Catalog::BannerThrottle::CooldownError)
        expect(reports.first).to be_handled
        expect(reports.first.context).to include(job_class: described_class.name)
      end
    end
  end
end

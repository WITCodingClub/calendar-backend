# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::IcsImport, type: :service do
  let(:feed_url) { described_class::ICS_FEED_URL }

  def stub_feed(fixture, url: feed_url, status: 200)
    stub_request(:get, url).to_return(status: status, body: file_fixture("university_calendar/#{fixture}").read)
  end

  def event_for(uid) = UniversityCalendarEvent.find_by!(ics_uid: uid)

  def at(*args) = Time.zone.local(*args)

  let!(:fall_term) do
    create(:term, year: 2026, season: :fall, start_date: Date.new(2026, 8, 31), end_date: Date.new(2026, 12, 18))
  end

  describe ".backfill_url" do
    it "adds the date range to the feed URL" do
      url = described_class.backfill_url(Date.new(2026, 1, 5), Time.zone.local(2026, 5, 1))

      expect(url).to eq("#{feed_url}?startdt=2026-01-05&enddt=2026-05-01")
    end
  end

  describe "#call" do
    context "with a normal feed" do
      let!(:request) { stub_feed("feed.ics") }
      let(:result) { described_class.call }

      it "creates one event for each usable entry and reports the counts" do
        expect { result }.to change(UniversityCalendarEvent, :count).by(11)

        expect(result).to include(created: 11, updated: 0, unchanged: 0, cancelled: 0, merged: 1, errors: [])
        expect(request).to have_been_requested.once
      end

      it "lists each changed category once" do
        expect(result[:changed_categories]).to match_array(
          %w[exhibit holiday deadline campus_event study_day term_dates graduation]
        )
      end

      it "stores a timed event with its decoded text, recurrence and organization" do
        result
        event = event_for("robotics-showcase@example.test")

        expect(event).to have_attributes(
          summary:        "Robotics Club Showcase & Demo",
          location:       "Example Hall Room 101",
          category:       "exhibit",
          all_day:        false,
          organization:   "Student Affairs",
          academic_term:  "Fall 2026",
          event_type_raw: "Student Showcase",
          recurrence:     [ "RRULE:FREQ=WEEKLY;COUNT=3" ],
          source_url:     feed_url,
          term:           fall_term
        )
        expect(event.start_time).to eq(at(2026, 9, 15, 14))
        expect(event.end_time).to eq(at(2026, 9, 15, 16))
        expect(event.last_fetched_at).to be_present
      end

      it "strips markup from the description and swaps in the full title" do
        result

        expect(event_for("robotics-showcase@example.test").description)
          .to eq("Event Name: Robotics Club Showcase & Demo\nJoin the club for demos & snacks.")
      end

      it "stores no recurrence for a single event" do
        result

        expect(event_for("campus-fair@example.test").recurrence).to be_nil
      end

      it "treats a DATE value as an all-day event that covers whole days" do
        result
        event = event_for("labor-day@example.test")

        expect(event).to have_attributes(category: "holiday", all_day: true)
        expect(event.start_time).to eq(at(2026, 9, 7).beginning_of_day)
        expect(event.end_time).to eq(at(2026, 9, 8).end_of_day.change(usec: 999_999))
      end

      it "treats the Microsoft all-day flag as an all-day event" do
        result
        event = event_for("campus-fair@example.test")

        expect(event).to have_attributes(category: "campus_event", all_day: true)
        expect(event.start_time).to eq(at(2026, 10, 1).beginning_of_day)
      end

      it "treats a noon start with a late-night end as an all-day event" do
        result
        event = event_for("withdraw-deadline@example.test")

        expect(event).to have_attributes(category: "deadline", all_day: true)
        expect(event.start_time).to eq(at(2026, 11, 6).beginning_of_day)
        expect(event.end_time.to_date).to eq(Date.new(2026, 11, 6))
      end

      it "ends an event that has no end time at its start time" do
        result
        event = event_for("commencement@example.test")

        expect(event).to have_attributes(category: "graduation", all_day: false)
        expect(event.end_time).to eq(event.start_time)
      end

      it "falls back to the Event Name field when the summary is empty" do
        result

        expect(event_for("alumni-mixer@example.test").summary).to eq("Alumni Mixer")
      end

      it "skips an entry that has no start time" do
        result

        expect(UniversityCalendarEvent.exists?(ics_uid: "no-start@example.test")).to be(false)
      end

      it "merges back-to-back all-day events with the same title into one event" do
        result
        event = event_for("merged:study-day-one@example.test+2")

        expect(event).to have_attributes(summary: "Study Day", category: "study_day", all_day: true)
        expect(event.start_time).to eq(at(2026, 12, 10).beginning_of_day)
        # The feed's DATE end is exclusive, and the importer keeps it as the last day.
        expect(event.end_time.to_date).to eq(Date.new(2026, 12, 12))
        expect(UniversityCalendarEvent.exists?(ics_uid: "study-day-two@example.test")).to be(false)
      end

      it "uses the date to pick a term for a boundary event and corrects the title" do
        result
        event = event_for("classes-begin@example.test")

        expect(event).to have_attributes(category: "term_dates", term: fall_term, academic_term: "Spring 2026")
        expect(event.summary).to eq("Classes Begin for Fall 2026")
      end

      it "assigns the fall term to a January event that names Fall" do
        result

        expect(event_for("grade-deadline@example.test").term).to eq(fall_term)
      end

      it "falls back to the term that holds the date when the term name has no season" do
        result

        expect(event_for("orientation-panel@example.test").term).to eq(fall_term)
        expect(event_for("orientation-evening@example.test").term).to eq(fall_term)
      end

      it "leaves the term empty when no term holds the date" do
        result

        expect(event_for("commencement@example.test").term).to be_nil
      end

      it "reports every event as unchanged on a second run" do
        described_class.call
        second = described_class.call

        expect(second).to include(created: 0, updated: 0, unchanged: 11, errors: [])
        expect(UniversityCalendarEvent.count).to eq(11)
      end
    end

    context "with events from different seasons" do
      let!(:spring_term) { create(:term, year: 2027, season: :spring) }
      let!(:summer_term) { create(:term, year: 2026, season: :summer) }

      before do
        stub_feed("seasons.ics")
        described_class.call
      end

      it "picks the term by the season and year in the term name" do
        expect(event_for("add-drop-spring@example.test").term).to eq(spring_term)
        expect(event_for("registration-summer@example.test").term).to eq(summer_term)
      end

      it "rewrites a term in the title when the date belongs to another season" do
        event = event_for("classes-end-summer@example.test")

        expect(event.term).to eq(fall_term)
        expect(event.summary).to eq("Classes End for Fall 2026")
      end

      it "keeps a title that does not name a term, even when the date belongs to another season" do
        event = event_for("classes-begin-spring@example.test")

        expect(event.term).to eq(fall_term)
        expect(event.summary).to eq("Classes Begin")
      end

      it "keeps the title when the term name has no season" do
        event = event_for("first-day-unnamed@example.test")

        expect(event.term).to eq(fall_term)
        expect(event.summary).to eq("First Day of Classes")
      end
    end

    context "when the feed URL uses the webcal scheme" do
      it "fetches it over https" do
        request = stub_feed("empty_calendar.ics")

        described_class.call(ics_url: feed_url.sub("https://", "webcal://"))

        expect(request).to have_been_requested
      end
    end

    context "when an event already exists" do
      it "updates it in place when the feed changes it" do
        existing = create(:university_calendar_event,
                          ics_uid:    "robotics-showcase@example.test",
                          summary:    "Robotics Club Showcase",
                          location:   "Old Room",
                          category:   "campus_event",
                          start_time: at(2026, 9, 15, 14),
                          end_time:   at(2026, 9, 15, 16))
        stub_feed("updated_event.ics")

        result = described_class.call

        expect(result).to include(created: 0, updated: 1, unchanged: 0)
        expect(existing.reload).to have_attributes(location: "Example Hall Room 202", organization: "Student Affairs", term: fall_term)
        expect(existing.start_time).to eq(at(2026, 9, 15, 15))
        expect(result[:changed_categories]).to eq([ "campus_event" ])
      end

      it "skips a new entry that matches another event's content exactly" do
        create(:university_calendar_event,
               ics_uid:    "other-source@example.test",
               summary:    "Orientation Panel",
               category:   "campus_event",
               start_time: at(2026, 10, 20, 11),
               end_time:   at(2026, 10, 20, 12))
        stub_feed("feed.ics")

        result = described_class.call

        expect(result).to include(created: 10, unchanged: 1)
        expect(UniversityCalendarEvent.where(summary: "Orientation Panel").count).to eq(1)
      end

      it "skips a new entry that closely resembles another event on the same day" do
        create(:university_calendar_event,
               ics_uid:    "other-source@example.test",
               summary:    "Campus Fair 2026",
               category:   "campus_event",
               start_time: at(2026, 10, 1).beginning_of_day,
               end_time:   at(2026, 10, 1).end_of_day)
        stub_feed("feed.ics")

        result = described_class.call

        expect(result).to include(created: 10, unchanged: 1)
        expect(UniversityCalendarEvent.exists?(ics_uid: "campus-fair@example.test")).to be(false)
      end

      it "turns single-day events into the merged event and removes the extra days" do
        first = create(:university_calendar_event, ics_uid: "study-day-one@example.test", summary: "Study Day",
                                                   category: "study_day", all_day: true,
                                                   start_time: at(2026, 12, 10).beginning_of_day,
                                                   end_time: at(2026, 12, 10).end_of_day)
        create(:university_calendar_event, ics_uid: "study-day-two@example.test", summary: "Study Day",
                                           category: "study_day", all_day: true,
                                           start_time: at(2026, 12, 11).beginning_of_day,
                                           end_time: at(2026, 12, 11).end_of_day)
        stub_feed("merged_study_days.ics")

        result = described_class.call

        expect(result).to include(created: 1, updated: 1, merged: 1)
        expect(first.reload.ics_uid).to eq("merged:study-day-one@example.test+2")
        expect(first.description).to eq("Library stays open late.")
        expect(UniversityCalendarEvent.pluck(:ics_uid))
          .to contain_exactly("merged:study-day-one@example.test+2", "study-day-far@example.test")
      end
    end

    context "when the feed cancels events" do
      it "removes the stored event, the merged event it started, and ignores unknown UIDs" do
        create(:university_calendar_event, ics_uid: "robotics-showcase@example.test", category: "exhibit")
        create(:university_calendar_event, ics_uid: "merged:study-day-one@example.test+2", category: "study_day",
                                           summary: "Study Day")
        survivor = create(:university_calendar_event, ics_uid: "kept@example.test", summary: "Kept Event")
        stub_feed("cancelled_events.ics")

        result = described_class.call

        expect(result).to include(cancelled: 2, created: 0, updated: 0)
        expect(result[:changed_categories]).to match_array(%w[exhibit study_day])
        expect(UniversityCalendarEvent.all).to contain_exactly(survivor)
      end

      it "does not count a stored event that has no category as a changed category" do
        create(:university_calendar_event, ics_uid: "robotics-showcase@example.test", category: nil)
        stub_feed("cancelled_events.ics")

        result = described_class.call

        expect(result).to include(cancelled: 1, changed_categories: [])
      end
    end

    context "with a feed that has no events" do
      it "returns empty counts for a calendar with no entries" do
        stub_feed("empty_calendar.ics")

        expect(described_class.call).to eq(
          created: 0, updated: 0, unchanged: 0, merged: 0, cancelled: 0, errors: [], changed_categories: []
        )
      end

      it "returns empty counts for an empty response body" do
        stub_request(:get, feed_url).to_return(status: 200, body: "")

        expect(described_class.call).to include(created: 0, errors: [])
      end
    end

    context "with malformed input" do
      it "imports nothing from text that is not a calendar" do
        stub_feed("malformed.ics")

        expect { described_class.call }.not_to change(UniversityCalendarEvent, :count)
      end

      it "reports an entry that cannot be saved and keeps the valid ones" do
        body = file_fixture("university_calendar/duplicate_uid.ics").read.sub("Astronomy Night", "")
        stub_request(:get, feed_url).to_return(status: 200, body: body)

        result = described_class.call

        expect(result[:created]).to eq(1)
        expect(result[:errors].size).to eq(1)
        expect(result[:errors].first).to match(/\AError saving event repeat@example\.test: .*Summary/)
      end

      it "reports an entry that fails while it is read and keeps going" do
        stub_feed("feed.ics")
        calls = 0
        allow_any_instance_of(described_class).to receive(:clean_description).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          calls += 1
          raise ArgumentError, "bad description" if calls == 1

          original.call(*args)
        end

        result = described_class.call

        expect(result[:errors]).to eq([ "Error processing event robotics-showcase@example.test: bad description" ])
        expect(result[:created]).to eq(10)
      end
    end

    context "when the same UID appears twice in one feed" do
      it "keeps one event and lets the later entry update it" do
        stub_feed("duplicate_uid.ics")

        result = described_class.call

        expect(result).to include(created: 1, updated: 1, errors: [])
        expect(event_for("repeat@example.test").summary).to eq("Astronomy Night")
      end
    end

    context "when the download fails" do
      it "raises with the HTTP status for a server error" do
        stub_feed("feed.ics", status: 500)

        expect { described_class.call }.to raise_error(RuntimeError, "Failed to fetch ICS feed: 500")
        expect(UniversityCalendarEvent.count).to eq(0)
      end

      it "raises with the HTTP status for a missing feed" do
        stub_request(:get, feed_url).to_return(status: 404, body: "")

        expect { described_class.call }.to raise_error(RuntimeError, "Failed to fetch ICS feed: 404")
      end

      it "raises a Faraday error when the request times out" do
        stub_request(:get, feed_url).to_timeout

        expect { described_class.call }.to raise_error(Faraday::Error)
      end
    end
  end

  describe "private helpers without a preloaded cache" do
    subject(:importer) { described_class.new }

    let(:attrs) do
      { ics_uid: "new@example.test", summary: "Campus Fair 2026", category: "campus_event",
        start_time: at(2026, 10, 1, 9), end_time: at(2026, 10, 1, 10) }
    end

    it "finds an exact content match in the database" do
      match = create(:university_calendar_event, summary: "Campus Fair 2026", category: "campus_event",
                                                 start_time: attrs[:start_time], end_time: attrs[:end_time])

      expect(importer.send(:find_duplicate_by_content, attrs)).to eq(match)
    end

    it "finds a fuzzy match in the database" do
      match = create(:university_calendar_event, summary: "Campus Fair", category: "campus_event",
                                                 start_time: attrs[:start_time], end_time: attrs[:end_time])

      expect(importer.send(:find_duplicate_by_content, attrs)).to eq(match)
    end

    it "returns nil when nothing resembles the entry" do
      expect(importer.send(:find_duplicate_by_content, attrs)).to be_nil
    end

    it "ignores the content cache when none was loaded" do
      event = build(:university_calendar_event)

      expect(importer.send(:add_event_to_content_cache, event)).to be_nil
    end
  end
end

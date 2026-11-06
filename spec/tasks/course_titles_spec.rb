# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "course title rake tasks" do
  include ActiveSupport::Testing::TimeHelpers

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  around do |example|
    travel_to(Date.new(2026, 11, 6)) { example.run }
  end

  let(:current_term) do
    create(:term, uid: 202710, season: :fall, year: 2026,
                  start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15))
  end
  let(:past_term) do
    create(:term, uid: 202520, season: :spring, year: 2025,
                  start_date: Date.new(2025, 1, 13), end_date: Date.new(2025, 5, 2))
  end

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  # SQL with a bind skips `normalizes`, as a title stored before this rule did.
  def course_with_stored_title(term, title)
    create(:course, term: term).tap do |course|
      Course.where(id: course.id).update_all([ "title = ?", title ])
    end
  end

  describe "courses:refresh_titles" do
    def banner_catalog(*rows)
      { success: true, courses: rows.map { |crn, title| { "courseReferenceNumber" => crn.to_s, "courseTitle" => title } } }
    end

    it "writes the Banner title again, which a stored title cannot give back" do
      course = course_with_stored_title(past_term, "Intro To Co - Op")
      allow(Catalog::LeopardWebClient).to receive(:get_course_catalog)
        .with(term: past_term.uid).and_return(banner_catalog([ course.crn, "INTRO TO CO-OP" ]))

      expect { run_task("courses:refresh_titles", past_term.uid.to_s) }.to output(/TOTAL: Updated 1, Failed 0/).to_stdout

      expect(course.reload.title).to eq("Intro To Co-Op")
    end

    it "refreshes every term that has courses when ALL=1" do
      past = course_with_stored_title(past_term, "Intro To Co - Op")
      current = course_with_stored_title(current_term, "Studio 07 (ai - Urbino)")
      allow(Catalog::LeopardWebClient).to receive(:get_course_catalog)
        .with(term: past_term.uid).and_return(banner_catalog([ past.crn, "INTRO TO CO-OP" ]))
      allow(Catalog::LeopardWebClient).to receive(:get_course_catalog)
        .with(term: current_term.uid).and_return(banner_catalog([ current.crn, "STUDIO 07 (AI-URBINO)" ], [ 99_999, "NOT STORED" ]))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ALL").and_return("1")

      expect { run_task("courses:refresh_titles") }.to output(/TOTAL: Updated 2, Failed 0/).to_stdout

      expect(past.reload.title).to eq("Intro To Co-Op")
      expect(current.reload.title).to eq("Studio 07 (AI-Urbino)")
    end

    it "skips a term that Banner does not answer for" do
      course = course_with_stored_title(current_term, "Intro To Co - Op")
      allow(Catalog::LeopardWebClient).to receive(:get_course_catalog)
        .and_return({ success: false, error: "timeout", courses: [] })

      expect { run_task("courses:refresh_titles", current_term.uid.to_s) }.to output(/Failed to fetch courses: timeout/).to_stdout

      expect(course.reload.title).to eq("Intro To Co - Op")
    end
  end

  describe "courses:normalize_titles" do
    it "formats a stored title of the current term and leaves a formatted title alone" do
      old = course_with_stored_title(current_term, "Agentic Ai And Intelligent Agents")
      formatted = create(:course, term: current_term, title: "CALCULUS II")

      expect { run_task("courses:normalize_titles") }.to output(/Updated 1 course titles/).to_stdout

      expect(old.reload.title).to eq("Agentic AI And Intelligent Agents")
      expect(formatted.reload.title).to eq("Calculus II")
    end

    it "marks the enrolled students of a changed course for a calendar sync" do
      course = course_with_stored_title(current_term, "Intro To Ai")
      create(:enrollment, course: course)
      allow(CourseCalendars::SyncMarker).to receive(:mark)

      expect { run_task("courses:normalize_titles") }.to output.to_stdout

      expect(CourseCalendars::SyncMarker).to have_received(:mark).with(course.id)
    end

    it "skips past terms unless ALL=1" do
      past = course_with_stored_title(past_term, "Intro To Ai")
      current_term

      expect { run_task("courses:normalize_titles") }.to output(/Updated 0 course titles/).to_stdout
      expect(past.reload.title).to eq("Intro To Ai")

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ALL").and_return("1")
      expect { run_task("courses:normalize_titles") }.to output(/Updated 1 course titles/).to_stdout
      expect(past.reload.title).to eq("Intro To AI")
    end
  end
end

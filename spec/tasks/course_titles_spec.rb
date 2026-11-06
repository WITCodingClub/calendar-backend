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

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  # SQL with a bind skips `normalizes`, as a title stored before this rule did.
  def course_with_stored_title(term, title)
    create(:course, term: term).tap do |course|
      Course.where(id: course.id).update_all([ "title = ?", title ])
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

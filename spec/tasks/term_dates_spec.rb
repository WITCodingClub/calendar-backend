# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "terms:fix_implausible_dates" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before { allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return(success: false, terms: []) }

  def run_task
    task = Rake::Task["terms:fix_implausible_dates"]
    task.reenable
    expect { task.invoke }.to output.to_stdout
  end

  it "clears dates from the wrong year and fills them again from the calendar" do
    summer = create(:term, year: 2031, season: :summer, start_date: Date.new(2030, 7, 25), end_date: Date.new(2030, 8, 11))
    create(:university_calendar_event, summary: "Summer 2031 Final Exam Period", category: "finals",
                                       start_time: Time.zone.local(2031, 8, 5, 9), end_time: Time.zone.local(2031, 8, 11, 17))

    run_task

    expect(summer.reload).to have_attributes(start_date: nil, end_date: Date.new(2031, 8, 11))
  end

  it "takes the dates from the term's courses when it has them" do
    fall = create(:term, year: 2031, season: :fall, start_date: Date.new(2030, 7, 25), end_date: Date.new(2030, 8, 11))
    create(:course, term: fall, start_date: Date.new(2031, 9, 8), end_date: Date.new(2031, 12, 15))

    run_task

    expect(fall.reload).to have_attributes(start_date: Date.new(2031, 9, 8), end_date: Date.new(2031, 12, 15))
  end

  it "leaves a term with plausible dates alone" do
    spring = create(:term, year: 2031, season: :spring, start_date: Date.new(2030, 10, 15), end_date: Date.new(2031, 4, 25))

    run_task

    expect(spring.reload).to have_attributes(start_date: Date.new(2030, 10, 15), end_date: Date.new(2031, 4, 25))
  end
end

# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "university_calendar:recategorize" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  around do |example|
    saved = ENV.fetch("DRY_RUN", nil)
    example.run
  ensure
    saved.nil? ? ENV.delete("DRY_RUN") : ENV["DRY_RUN"] = saved
  end

  let!(:announcement) do
    create(:university_calendar_event, summary: "Spring 2027 Final Exam Schedule Available to Students", category: "finals")
  end

  before { allow(UniversityCalendar::SyncJob).to receive(:resync_users) }

  def run_task
    task = Rake::Task["university_calendar:recategorize"]
    task.reenable
    task.invoke
  end

  it "prints the changes and saves nothing by default" do
    ENV.delete("DRY_RUN")

    expect { run_task }.to output(/finals -> academic.*Would change 1 events/m).to_stdout
    expect(announcement.reload.category).to eq("finals")
  end

  it "saves the changes and queues the syncs with DRY_RUN=0" do
    ENV["DRY_RUN"] = "0"

    expect { run_task }.to output(/Changed 1 events/).to_stdout
    expect(announcement.reload.category).to eq("academic")
    expect(UniversityCalendar::SyncJob).to have_received(:resync_users).with(contain_exactly("finals", "academic"))
  end

  [ "false", "" ].each do |value|
    it "treats DRY_RUN=#{value.inspect} as #{value.empty? ? 'unset, so it only prints' : 'a real run'}" do
      ENV["DRY_RUN"] = value

      expect { run_task }.to output.to_stdout
      expect(announcement.reload.category).to eq(value.empty? ? "finals" : "academic")
    end
  end

  it "still only prints with DRY_RUN=1" do
    ENV["DRY_RUN"] = "1"

    expect { run_task }.to output(/Would change 1 events/).to_stdout
    expect(announcement.reload.category).to eq("finals")
  end
end

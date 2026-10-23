# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "degree_requirements rake tasks" do
  include ActiveSupport::Testing::TimeHelpers

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  it "queues the import of one catalog year" do
    expect { run_task("degree_requirements:import", "2024") }
      .to have_enqueued_job(DegreeRequirements::ImportJob).with(2024)
      .and output(/Queued the import of 2024-2025/).to_stdout
  end

  it "queues every year from 2019 to this year" do
    travel_to Date.new(2026, 10, 22) do
      expect { run_task("degree_requirements:import_all") }
        .to have_enqueued_job(DegreeRequirements::ImportJob).exactly(8).times
        .and output(/Queued 2019..2026/).to_stdout
    end
  end
end

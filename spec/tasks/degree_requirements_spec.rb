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
      .to have_enqueued_job(DegreeRequirements::ImportJob).with(2024, force: false)
      .and output(/Queued the import of 2024-2025\./).to_stdout
  end

  it "passes FORCE on to the job" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FORCE").and_return("1")

    expect { run_task("degree_requirements:import", "2024") }
      .to have_enqueued_job(DegreeRequirements::ImportJob).with(2024, force: true)
      .and output(/with force/).to_stdout
  end

  it "queues every year from 2013, the first year with Banner data, to this year" do
    travel_to Date.new(2026, 10, 22) do
      expect { run_task("degree_requirements:import_all") }
        .to have_enqueued_job(DegreeRequirements::ImportJob).exactly(14).times
        .and output(/Queued 2013..2026/).to_stdout
    end
  end

  it "finds the course code aliases" do
    allow(DegreeRequirements::AliasFinder).to receive(:call)
      .and_return(DegreeRequirements::AliasFinder::Result.new(added: 3, title_match: 2, banner: 1))

    expect { run_task("degree_requirements:aliases") }
      .to output(%r{Added 3 aliases \(2 from the catalogs, 1 from Banner\).*/admin/catalog_reviews}).to_stdout
  end
end

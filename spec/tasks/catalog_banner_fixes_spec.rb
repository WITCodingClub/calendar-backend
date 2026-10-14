# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "catalog Banner fix rake tasks" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  let!(:old_term)    { create(:term, year: 2020, season: :fall) }
  let!(:future_term) { create(:term, year: 2031, season: :spring) }

  before do
    allow(Term).to receive(:current_and_future).and_return(Term.where(id: future_term.id))
    allow(Term).to receive(:active).and_return(Term.none)
  end

  describe "catalog:backfill_section_links" do
    it "enqueues the terms with linked sections, current and future terms first" do
      create(:course, term: old_term, is_section_linked: true)
      create(:course, term: future_term, is_section_linked: true)
      create(:term, year: 2019) # no linked sections

      expect { run_task("catalog:backfill_section_links") }.to output(/2 terms/).to_stdout

      uids = enqueued_jobs.select { |job| job["job_class"] == "Catalog::SectionLinksSyncJob" }.map { |job| job["arguments"].first }
      expect(uids).to eq([ future_term.uid, old_term.uid ])
    end
  end

  describe "catalog:repair_credit_hours" do
    it "enqueues a repair for each term with courses, current and future terms first" do
      create(:course, term: old_term)
      create(:course, term: future_term)

      expect { run_task("catalog:repair_credit_hours") }.to output(/2 terms/).to_stdout

      uids = enqueued_jobs.select { |job| job["job_class"] == "Catalog::CreditHoursRepairJob" }.map { |job| job["arguments"].first }
      expect(uids).to eq([ future_term.uid, old_term.uid ])
    end
  end
end

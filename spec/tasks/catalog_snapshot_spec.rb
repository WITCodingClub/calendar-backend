# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "catalog_snapshot rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  it "exports the catalog to FILE and imports it back into empty tables" do
    course = create(:course, term: create(:term, uid: 202710, year: 2026, season: :fall))

    Dir.mktmpdir do |dir|
      path = File.join(dir, "catalog.json.gz")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("FILE", anything).and_return(path)

      expect { run_task("catalog_snapshot:export") }.to output(/Wrote #{Regexp.escape(path)}: 1 terms.*1 courses/).to_stdout

      CatalogSnapshot::TABLES.values.reverse_each { |model, _columns| model.constantize.delete_all }

      expect { run_task("catalog_snapshot:import") }.to output(/Imported #{Regexp.escape(path)}/).to_stdout
      expect(Course.find(course.id).crn).to eq(course.crn)
    end
  end
end

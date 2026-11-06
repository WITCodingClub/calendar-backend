# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "course title rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  describe "courses:normalize_titles" do
    it "formats a stored title again and leaves a formatted title alone" do
      old = create(:course)
      # SQL with a bind skips `normalizes`, as a title stored before this rule did.
      Course.where(id: old.id).update_all([ "title = ?", "Agentic Ai And Intelligent Agents" ])
      current = create(:course, title: "CALCULUS II")

      expect { run_task("courses:normalize_titles") }.to output(/Updated 1 course titles/).to_stdout

      expect(old.reload.title).to eq("Agentic AI And Intelligent Agents")
      expect(current.reload.title).to eq("Calculus II")
    end
  end
end

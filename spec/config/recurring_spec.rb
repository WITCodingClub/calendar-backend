# frozen_string_literal: true

require "rails_helper"

# Solid Queue only reads recurring.yml in production, so a typo in a class
# name or command shows up there as a failed job, not at boot.
RSpec.describe "config/recurring.yml" do
  tasks = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")

  tasks.each do |key, task|
    it "#{key} points at code that exists" do
      if task["class"]
        expect(task["class"].safe_constantize).to be < ActiveJob::Base
      else
        receiver, method = task.fetch("command").match(/\A([\w:]+)\.(\w+[!?]?)/).captures

        expect(receiver.constantize).to respond_to(method)
      end
    end
  end
end

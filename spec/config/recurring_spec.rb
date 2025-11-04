# frozen_string_literal: true

require "rails_helper"

RSpec.describe "recurring.yml configuration", type: :config do
  let(:config) { YAML.safe_load_file(Rails.root.join("config/recurring.yml")) }

  it "loads successfully" do
    expect(config).to be_a(Hash)
  end

  it "includes the update_faculty_rmp_ratings job" do
    expect(config).to have_key("update_faculty_rmp_ratings")
  end

  describe "update_faculty_rmp_ratings job" do
    let(:job_config) { config["update_faculty_rmp_ratings"] }

    it "has the correct command" do
      expect(job_config["command"]).to eq("Faculty.update_all_ratings!")
    end

    it "has the correct schedule" do
      expect(job_config["schedule"]).to eq("every sunday at 3am")
    end
  end
end

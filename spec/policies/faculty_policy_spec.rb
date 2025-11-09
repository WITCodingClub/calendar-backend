# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacultyPolicy, type: :policy do
  it_behaves_like "public-read resource policy", :faculty
end

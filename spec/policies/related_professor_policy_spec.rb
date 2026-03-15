# frozen_string_literal: true

require "rails_helper"

RSpec.describe RelatedProfessorPolicy, type: :policy do
  it_behaves_like "public-read resource policy", :related_professor
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FacultyPolicy, type: :policy do
  include_examples "public-read resource policy", :faculty
end

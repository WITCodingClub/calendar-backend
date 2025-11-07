# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoursePolicy, type: :policy do
  include_examples "public-read resource policy", :course
end

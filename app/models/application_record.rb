# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  has_paper_trail
  extend FriendlyId

  include PgSearch::Model

end

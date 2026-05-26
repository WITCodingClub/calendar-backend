# frozen_string_literal: true

class Course::ScheduleType
  TYPES = {
    extension:           { code: "EXT", readable_description: "extension" },
    hybrid:              { code: "HYB", readable_description: "hybrid in-person and online" },
    independent_study:   { code: "IND", readable_description: "independent study" },
    laboratory:          { code: "LAB", readable_description: "laboratory hands-on" },
    lecture:             { code: "LEC", readable_description: "lecture" },
    online:              { code: "ONL", readable_description: "online asynchronous" },
    online_blended:      { code: "ONB", readable_description: "online blended" },
    online_sync_lab:     { code: "OLB", readable_description: "online synchronous lab" },
    online_sync_lecture: { code: "OLC", readable_description: "online synchronous lecture" },
    rotating_lab:        { code: "RLB", readable_description: "rotating laboratory" },
    rotating_lecture:    { code: "RLC", readable_description: "rotating lecture" },
    study_abroad:        { code: "SAB", readable_description: "study abroad" }
  }.freeze

  attr_reader :type

  def initialize(key)
    @type = TYPES.fetch(key.to_sym) { raise ArgumentError, "Unknown schedule type: #{key}" }
  end

  def code                 = type[:code]
  def readable_description = type[:readable_description]

  def self.valid?(key)
    TYPES.key?(key.to_sym)
  end
end

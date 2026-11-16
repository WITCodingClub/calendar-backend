# frozen_string_literal: true

class Course::ScheduleType
  TYPES = {
    extension:           { code: "EXT", readable_description: "extension" },
    hybrid:              { code: "HYB", readable_description: "hybrid in-person and online" },
    independent_study:   { code: "IND", readable_description: "independent study" },
    laboratory:          { code: "LAB", readable_description: "laboratory hands-on", lab: true },
    lecture:             { code: "LEC", readable_description: "lecture" },
    online:              { code: "ONL", readable_description: "online asynchronous", online: true },
    online_blended:      { code: "ONB", readable_description: "online blended", online: true },
    online_sync_lab:     { code: "OLB", readable_description: "online synchronous lab", lab: true, online: true },
    online_sync_lecture: { code: "OLC", readable_description: "online synchronous lecture", online: true },
    rotating_lab:        { code: "RLB", readable_description: "rotating laboratory", lab: true },
    rotating_lecture:    { code: "RLC", readable_description: "rotating lecture" },
    study_abroad:        { code: "SAB", readable_description: "study abroad" },
    study_away_domestic: { code: "SAD", readable_description: "study away domestic" }
  }.freeze

  attr_reader :type

  def initialize(key)
    @type = TYPES.fetch(key.to_sym) { raise ArgumentError, "Unknown schedule type: #{key}" }
  end

  def code                 = type[:code]
  def readable_description = type[:readable_description]
  def lab?                 = type.fetch(:lab, false)
  # An online section can meet with no building.
  def online?              = type.fetch(:online, false)

  def self.valid?(key) = TYPES.key?(key.to_sym)
  def self.key_for_code(code) = TYPES.find { |_k, v| v[:code] == code.to_s.upcase }&.first&.to_s

  # false for a blank or unknown key.
  def self.lab?(key)    = valid_key?(key) && new(key).lab?
  def self.online?(key) = valid_key?(key) && new(key).online?

  def self.valid_key?(key) = key.present? && valid?(key)
  private_class_method :valid_key?
end

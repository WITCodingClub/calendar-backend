# frozen_string_literal: true

module Catalog
  # The subjects that have active sections, with section counts. The REST
  # controller, the GraphQL schema, and the MCP server use this object.
  class SubjectQuery
    # @return [Array<Hash>] { subject:, code:, section_count: }, by subject
    def call(term_uid: nil)
      scope = Course.active
      scope = scope.where(term_id: Term.where(uid: term_uid.to_i).select(:id)) if term_uid.present?

      scope.group(:subject).count.sort_by { |subject, _| subject }.map do |subject, count|
        { subject: subject, code: self.class.code_for(subject), section_count: count }
      end
    end

    # The subject codes (COMP, MATH) with active sections, sorted. Cheaper than
    # call: it counts nothing. The MCP server completes prompt arguments with it.
    #
    # @return [Array<String>]
    # term_uids: only the subjects of these terms. nil: every term.
    def codes(term_uids: nil)
      scope = Course.active
      scope = scope.where(term_id: Term.where(uid: Array(term_uids).map(&:to_i)).select(:id)) unless term_uids.nil?

      scope.distinct.pluck(:subject).map { |subject| self.class.code_for(subject) }.uniq.sort
    end

    # Stored as "Computer Science (COMP)"; students search by the code.
    def self.code_for(subject)
      subject =~ /\(([^)]+)\)/ ? ::Regexp.last_match(1) : subject
    end
  end
end

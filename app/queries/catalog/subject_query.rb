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

    # Stored as "Computer Science (COMP)"; students search by the code.
    def self.code_for(subject)
      subject =~ /\(([^)]+)\)/ ? ::Regexp.last_match(1) : subject
    end
  end
end

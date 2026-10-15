# frozen_string_literal: true

module Oauth
  # The scope checkboxes on the consent page, and the scopes the student
  # approved with them (McpTools::Scopes).
  #
  # A box starts checked when its scope is a default, when the student gave
  # it to this app before, or when the client asked for fewer than all
  # scopes. A client that asks for fewer is asking for what one tool call
  # needs (step-up authorization), so the box it names starts checked.
  class ConsentScopes
    Item = Data.define(:scope, :checked)

    # requested: the scope string of the authorization request.
    # previous:  the scope string of the student's last token for this app,
    #            or nil.
    def initialize(requested, previous: nil)
      @requested = McpTools::Scopes.expand(requested.presence || McpTools::Scopes::ALWAYS)
      @previous  = McpTools::Scopes.expand(previous)
    end

    # The scope string to send through the consent form. The legacy read
    # scope becomes the read scopes it stands for.
    def requested_scope
      (@requested | [ McpTools::Scopes::ALWAYS ]).join(" ")
    end

    # Checkbox items in McpTools::Scopes order, grouped by :read and :change.
    # The always-on scope has no box.
    def groups
      McpTools::Scopes::ALL
        .select { |scope| scope.name != McpTools::Scopes::ALWAYS && @requested.include?(scope.name) }
        .map { |scope| Item.new(scope: scope, checked: checked?(scope)) }
        .group_by { |item| item.scope.group }
    end

    # The scope string to grant: the always-on scope and each requested scope
    # whose box was checked.
    def granted_scope(checked_names)
      checked = Array(checked_names).map(&:to_s)
      granted = @requested.select { |name| name == McpTools::Scopes::ALWAYS || checked.include?(name) }
      (granted | [ McpTools::Scopes::ALWAYS ]).join(" ")
    end

    private

    def checked?(scope)
      scope.default || @previous.include?(scope.name) || narrow_request?
    end

    def narrow_request?
      (McpTools::Scopes::NAMES - @requested).any?
    end
  end
end

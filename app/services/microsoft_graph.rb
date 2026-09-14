# frozen_string_literal: true

# Settings and errors for the Microsoft Graph calendar provider.
#
# The provider is off unless the app has an Entra client (MICROSOFT_CLIENT_ID
# and MICROSOFT_CLIENT_SECRET) and the Flipper flag is on for the person. The
# WIT tenant does not let people consent to calendar scopes themselves, so an
# IT admin must grant consent before the flag goes on. See
# docs/microsoft-graph-calendar.md.
module MicrosoftGraph
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      super(message)
      @status = status
      @body   = body
    end
  end

  class NotFoundError < Error; end
  class AuthError < Error; end

  # Delegated scopes. openid, email and profile identify the account;
  # offline_access returns a refresh token. MailboxSettings.ReadWrite reads and
  # creates the Outlook categories that color events.
  SCOPES = %w[openid email profile offline_access Calendars.ReadWrite MailboxSettings.ReadWrite].freeze

  module_function

  def config
    {
      client_id:     ENV["MICROSOFT_CLIENT_ID"].presence,
      client_secret: ENV["MICROSOFT_CLIENT_SECRET"].presence,
      tenant_id:     ENV["MICROSOFT_TENANT_ID"].presence || "organizations",
      redirect_uri:  ENV["MICROSOFT_REDIRECT_URI"].presence
    }
  end

  def configured?
    settings = config
    settings[:client_id].present? && settings[:client_secret].present?
  end

  def enabled_for?(user)
    return false unless user && configured?

    Flipper.enabled?(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user)
  end
end

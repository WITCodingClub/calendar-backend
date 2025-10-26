class MagicLinkMailer < ApplicationMailer
  def send_link(magic_link)
    @magic_link = magic_link
    @user = magic_link.user
    @login_url = "#{ENV.fetch('APP_URL', 'http://localhost:3000')}/magic_link/verify?token=#{magic_link.token}"

    mail(
      to: @user.email,
      subject: "Sign in to WIT Calendar"
    )
  end
end

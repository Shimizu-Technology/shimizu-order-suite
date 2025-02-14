class PasswordMailer < ApplicationMailer
  default from: 'Hafaloha <4lmshimizu@gmail.com>'

  def reset_password(user, raw_token)
    @user = user
    @url  = "#{ENV['FRONTEND_URL']}/ordering/reset-password?token=#{raw_token}&email=#{user.email}"

    mail(to: @user.email, subject: "Reset your Hafaloha password")
  end
end

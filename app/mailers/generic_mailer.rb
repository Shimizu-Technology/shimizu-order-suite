# app/mailers/generic_mailer.rb
class GenericMailer < ApplicationMailer
  def custom_email(to:, subject:, body:, from_name: nil)
    @body = body.html_safe
    
    # Set the from address with an optional custom name
    from_address = '4lmshimizu@gmail.com'
    mail_from = from_name.present? ? "#{from_name} <#{from_address}>" : from_address
    
    mail(
      to: to,
      subject: subject,
      from: mail_from
    )
  end
end

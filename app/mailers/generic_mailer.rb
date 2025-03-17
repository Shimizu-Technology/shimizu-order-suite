# app/mailers/generic_mailer.rb
class GenericMailer < ApplicationMailer
  def custom_email(to_email, subject, template_content, restaurant)
    @content = template_content
    @restaurant = restaurant
    @header_color = email_header_color_for(@restaurant)

    mail(
      to: to_email,
      from: restaurant_from_address(@restaurant),
      subject: subject
    )
  end
end

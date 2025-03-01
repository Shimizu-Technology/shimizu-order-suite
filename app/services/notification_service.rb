# app/services/notification_service.rb
class NotificationService
  def self.send_notification(type, recipient, data = {})
    # Get restaurant_id from data or default to 1
    restaurant_id = data[:restaurant_id] || 1
    restaurant = Restaurant.find(restaurant_id)
    
    # Get frontend_id from data or use default
    frontend_id = data[:frontend_id] || restaurant.frontend_id || 'default'
    
    # Add restaurant data to the template context
    context = data.merge(
      restaurant_name: restaurant.name,
      restaurant_address: restaurant.address,
      restaurant_phone: restaurant.phone_number,
      frontend_id: frontend_id
    )
    
    # Add any frontend-specific data
    context = add_frontend_specific_data(context, frontend_id)
    
    Rails.logger.info("[NotificationService] Sending #{type} notification to #{recipient.inspect} for frontend #{frontend_id}")
    
    # Send email if we have an email address
    if recipient[:email].present?
      Rails.logger.info("[NotificationService] Sending email to #{recipient[:email]}")
      send_email_notification(type, recipient[:email], context)
    end
    
    # Send SMS if we have a phone number
    if recipient[:phone].present?
      Rails.logger.info("[NotificationService] Sending SMS to #{recipient[:phone]}")
      send_sms_notification(type, recipient[:phone], context)
    end
    
    # Send WhatsApp if we have a group_id
    if recipient[:whatsapp_group_id].present?
      Rails.logger.info("[NotificationService] Sending WhatsApp to #{recipient[:whatsapp_group_id]}")
      send_whatsapp_notification(type, recipient[:whatsapp_group_id], context)
    end
  end
  
  # Add frontend-specific data to the context
  def self.add_frontend_specific_data(context, frontend_id)
    # This method can be extended to add more frontend-specific data
    # For now, we'll just add a few basic fields
    
    case frontend_id
    when 'hafaloha'
      context.merge!(
        brand_color: '#c1902f',
        logo_url: 'https://hafaloha.com/logo.png',
        footer_text: 'Mahalo for your order!',
        social_media: {
          facebook: 'https://facebook.com/hafaloha',
          instagram: 'https://instagram.com/hafaloha'
        }
      )
    when 'sushi_spot'
      context.merge!(
        brand_color: '#e74c3c',
        logo_url: 'https://sushi-spot.com/logo.png',
        footer_text: 'Thank you for your order!',
        social_media: {
          facebook: 'https://facebook.com/sushi-spot',
          instagram: 'https://instagram.com/sushi-spot'
        }
      )
    else
      # Default frontend data
      context.merge!(
        brand_color: '#333333',
        logo_url: context[:restaurant_logo_url] || '',
        footer_text: 'Thank you for your business!',
        social_media: {}
      )
    end
    
    # Add site settings for this restaurant, or global settings if not found
    site_settings = SiteSetting.for_restaurant(context[:restaurant_id])
    if site_settings
      context[:site_settings] = {
        hero_image_url: site_settings.hero_image_url,
        spinner_image_url: site_settings.spinner_image_url
      }
    end
    
    context
  end
  
  private
  
  def self.send_email_notification(type, email, data)
    # Try to find a template for this specific frontend
    template = NotificationTemplate.find_for_restaurant_and_frontend(
      type, 'email', data[:restaurant_id], data[:frontend_id]
    )
    
    unless template
      Rails.logger.error("[NotificationService] No email template found for #{type} and frontend #{data[:frontend_id]}")
      return
    end
    
    Rails.logger.info("[NotificationService] Found email template: #{template.id}")
    
    # Render the template with the data
    subject = TemplateRenderer.render(template.subject, data)
    body = TemplateRenderer.render(template.content, data)
    
    Rails.logger.info("[NotificationService] Rendered email subject: #{subject}")
    Rails.logger.info("[NotificationService] Data for rendering: #{data.inspect}")
    
    # Send the email
    begin
      mail = GenericMailer.custom_email(
        to: email,
        subject: subject,
        body: body,
        from_name: template.sender_name || data[:restaurant_name]
      )
      mail.deliver_later
      Rails.logger.info("[NotificationService] Email queued for delivery to #{email}")
    rescue => e
      Rails.logger.error("[NotificationService] Failed to send email: #{e.message}")
    end
  end
  
  def self.send_sms_notification(type, phone, data)
    # Try to find a template for this specific frontend
    template = NotificationTemplate.find_for_restaurant_and_frontend(
      type, 'sms', data[:restaurant_id], data[:frontend_id]
    )
    
    unless template
      Rails.logger.error("[NotificationService] No SMS template found for #{type} and frontend #{data[:frontend_id]}")
      return
    end
    
    Rails.logger.info("[NotificationService] Found SMS template: #{template.id}")
    
    # Render the template with the data
    message = TemplateRenderer.render(template.content, data)
    
    Rails.logger.info("[NotificationService] Rendered SMS message: #{message}")
    Rails.logger.info("[NotificationService] Data for rendering: #{data.inspect}")
    
    # Check if ClickSend credentials are available
    if ENV['CLICKSEND_USERNAME'].blank? || ENV['CLICKSEND_API_KEY'].blank?
      Rails.logger.error("[NotificationService] Missing ClickSend credentials")
      return
    end
    
    # Send the SMS
    begin
      SendSmsJob.perform_later(
        to: phone,
        body: message,
        from: template.sender_name || data[:restaurant_name]
      )
      Rails.logger.info("[NotificationService] SMS job queued for #{phone}")
    rescue => e
      Rails.logger.error("[NotificationService] Failed to queue SMS job: #{e.message}")
    end
  end
  
  def self.send_whatsapp_notification(type, group_id, data)
    # Try to find a template for this specific frontend
    template = NotificationTemplate.find_for_restaurant_and_frontend(
      type, 'whatsapp', data[:restaurant_id], data[:frontend_id]
    )
    
    unless template
      Rails.logger.error("[NotificationService] No WhatsApp template found for #{type} and frontend #{data[:frontend_id]}")
      return
    end
    
    Rails.logger.info("[NotificationService] Found WhatsApp template: #{template.id}")
    
    # Render the template with the data
    message = TemplateRenderer.render(template.content, data)
    
    Rails.logger.info("[NotificationService] Rendered WhatsApp message: #{message}")
    Rails.logger.info("[NotificationService] Data for rendering: #{data.inspect}")
    
    # Send the WhatsApp message
    begin
      SendWhatsappJob.perform_later(group_id, message)
      Rails.logger.info("[NotificationService] WhatsApp job queued for #{group_id}")
    rescue => e
      Rails.logger.error("[NotificationService] Failed to queue WhatsApp job: #{e.message}")
    end
  end
end

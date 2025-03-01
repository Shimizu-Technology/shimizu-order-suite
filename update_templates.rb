#!/usr/bin/env ruby
# update_templates.rb

# Order Confirmation SMS
order_confirmation_sms = NotificationTemplate.find_or_create_by(
  notification_type: 'order_confirmation',
  channel: 'sms',
  restaurant_id: nil
)
order_confirmation_sms.update!(
  content: "Hi {{ customer_name }}, thanks for ordering from {{ restaurant_name }}! Order #{{ order_id }}: {{ items }}, total: ${{ total }}. We'll text you an ETA once we start preparing your order!",
  active: true
)
puts "Updated order_confirmation SMS template"

# Order Preparing SMS
order_preparing_sms = NotificationTemplate.find_or_create_by(
  notification_type: 'order_preparing',
  channel: 'sms',
  restaurant_id: nil
)
order_preparing_sms.update!(
  content: "Hi {{ customer_name }}, your order #{{ order_id }} is now being prepared! ETA: {{ eta }}.",
  active: true
)
puts "Updated order_preparing SMS template"

# Order Ready SMS
order_ready_sms = NotificationTemplate.find_or_create_by(
  notification_type: 'order_ready',
  channel: 'sms',
  restaurant_id: nil
)
order_ready_sms.update!(
  content: "Hi {{ customer_name }}, your order #{{ order_id }} is now ready for pickup! Thank you for choosing {{ restaurant_name }}.",
  active: true
)
puts "Updated order_ready SMS template"

# Order Confirmation Email
order_confirmation_email = NotificationTemplate.find_or_create_by(
  notification_type: 'order_confirmation',
  channel: 'email',
  restaurant_id: nil
)
order_confirmation_email.update!(
  subject: "Your {{ restaurant_name }} Order Confirmation #{{ order_id }}",
  content: <<~HTML
    <table width="100%" border="0" cellspacing="0" cellpadding="0"
           style="background-color: #f8f8f8; padding: 20px 0; font-family: Arial, sans-serif;">
      <tr>
        <td align="center">
          <table width="600" border="0" cellspacing="0" cellpadding="0"
                 style="background-color: #ffffff; border-radius: 6px; overflow: hidden;">
            
            <!-- HEADER -->
            <tr>
              <td align="center" style="background-color: #c1902f; padding: 20px;">
                <h1 style="margin: 0; font-size: 24px; color: #ffffff;
                           font-family: 'Helvetica Neue', Arial, sans-serif;">
                  {{ restaurant_name }} Order Confirmation
                </h1>
              </td>
            </tr>

            <!-- SPACER -->
            <tr><td style="height: 20px;">&nbsp;</td></tr>

            <!-- MAIN CONTENT -->
            <tr>
              <td style="padding: 0 30px 20px;">
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Hi <strong>{{ customer_name }}</strong>,
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Thank you for your order! Below are your details:
                </p>

                <!-- Order Details -->
                <table width="100%" border="0" cellspacing="0" cellpadding="0"
                       style="margin-bottom: 15px; font-size: 16px; color: #333;">
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Order ID:</strong> {{ order_id }}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Total:</strong> ${{ total }}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Items:</strong> {{ items }}
                    </td>
                  </tr>

                  {% if special_instructions %}
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Special Instructions:</strong>
                      {{ special_instructions }}
                    </td>
                  </tr>
                  {% endif %}

                  <!-- Always show the same pickup time message -->
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Pickup Time:</strong>
                      We'll send you another message with your ETA as soon as we start preparing your order.
                    </td>
                  </tr>
                </table>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  We'll contact you at <strong>{{ contact_phone }}</strong> if we have questions.
                </p>

                <p style="margin: 0; color: #333; font-size: 16px; line-height: 24px;">
                  We appreciate your business!
                </p>
              </td>
            </tr>

            <!-- FOOTER -->
            <tr>
              <td style="padding: 20px 30px; background-color: #f2f2f2;
                         color: #555; font-size: 14px; line-height: 20px;
                         border-top: 1px solid #ddd;">
                <p style="margin: 0;">
                  <strong>{{ restaurant_name }}</strong><br/>
                  {{ restaurant_address }} | {{ restaurant_phone }}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  HTML
)
puts "Updated order_confirmation Email template"

puts "All templates updated successfully!"

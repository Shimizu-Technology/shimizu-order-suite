# db/seeds/notification_templates.rb
# This file contains the default notification templates for the system

# Clear existing templates
puts "Clearing existing notification templates..."
NotificationTemplate.where(restaurant_id: nil).destroy_all

# Helper method to create a template
def create_template(type, channel, subject, content, sender_name = nil)
  NotificationTemplate.create!(
    notification_type: type,
    channel: channel,
    subject: subject,
    content: content,
    sender_name: sender_name,
    restaurant_id: nil, # nil means system default
    active: true
  )
end

puts "Creating default notification templates..."

# Order Confirmation - Email
create_template(
  'order_confirmation',
  'email',
  'Your \{\{ restaurant_name \}\} Order Confirmation #\{\{ order_id \}\}',
  <<~HTML
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
                  \{\{ restaurant_name \}\} Order Confirmation
                </h1>
              </td>
            </tr>

            <!-- SPACER -->
            <tr><td style="height: 20px;">&nbsp;</td></tr>

            <!-- MAIN CONTENT -->
            <tr>
              <td style="padding: 0 30px 20px;">
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Hi <strong>\{\{ customer_name \}\}</strong>,
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Thank you for your order! Below are your details:
                </p>

                <!-- Order Details -->
                <table width="100%" border="0" cellspacing="0" cellpadding="0"
                       style="margin-bottom: 15px; font-size: 16px; color: #333;">
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Order ID:</strong> \{\{ order_id \}\}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Total:</strong> $\{\{ total \}\}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Items:</strong> \{\{ items \}\}
                    </td>
                  </tr>

                  \{% if special_instructions \%}
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Special Instructions:</strong>
                      \{\{ special_instructions \}\}
                    </td>
                  </tr>
                  \{% endif \%}

                  <!-- Always show the same pickup time message -->
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Pickup Time:</strong>
                      We'll send you another message with your ETA as soon as we start preparing your order.
                    </td>
                  </tr>
                </table>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  We'll contact you at <strong>\{\{ contact_phone \}\}</strong> if we have questions.
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
                  <strong>\{\{ restaurant_name \}\}</strong><br/>
                  \{\{ restaurant_address \}\} | \{\{ restaurant_phone \}\}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  HTML
)

# Order Confirmation - SMS
create_template(
  'order_confirmation',
  'sms',
  nil,
  "Hi \{\{ customer_name \}\}, thanks for ordering from \{\{ restaurant_name \}\}! Order #\{\{ order_id \}\}: \{\{ items \}\}, total: $\{\{ total \}\}. We will text you an ETA once we start preparing your order!"
)

# Order Ready - Email
create_template(
  'order_ready',
  'email',
  'Your \{\{ restaurant_name \}\} Order #\{\{ order_id \}\} is Ready!',
  <<~HTML
    <table width="100%" border="0" cellspacing="0" cellpadding="0"
           style="background-color: #f8f8f8; padding: 20px 0; font-family: Arial, sans-serif;">
      <tr>
        <td align="center">
          <table width="600" border="0" cellspacing="0" cellpadding="0"
                 style="background-color: #ffffff; border-radius: 6px; overflow: hidden;">
            
            <!-- HEADER -->
            <tr>
              <td align="center" style="background-color: #4CAF50; padding: 20px;">
                <h1 style="margin: 0; font-size: 24px; color: #ffffff;
                           font-family: 'Helvetica Neue', Arial, sans-serif;">
                  Your Order is Ready!
                </h1>
              </td>
            </tr>

            <!-- SPACER -->
            <tr><td style="height: 20px;">&nbsp;</td></tr>

            <!-- MAIN CONTENT -->
            <tr>
              <td style="padding: 0 30px 20px;">
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Hi <strong>\{\{ customer_name \}\}</strong>,
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Great news! Your order #\{\{ order_id \}\} is now ready for pickup.
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Please come to our location to pick up your order. If you have any questions, 
                  feel free to call us at \{\{ restaurant_phone \}\}.
                </p>

                <p style="margin: 0; color: #333; font-size: 16px; line-height: 24px;">
                  Thank you for choosing \{\{ restaurant_name \}\}!
                </p>
              </td>
            </tr>

            <!-- FOOTER -->
            <tr>
              <td style="padding: 20px 30px; background-color: #f2f2f2;
                         color: #555; font-size: 14px; line-height: 20px;
                         border-top: 1px solid #ddd;">
                <p style="margin: 0;">
                  <strong>\{\{ restaurant_name \}\}</strong><br/>
                  \{\{ restaurant_address \}\} | \{\{ restaurant_phone \}\}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  HTML
)

# Order Ready - SMS
create_template(
  'order_ready',
  'sms',
  nil,
  "Hi \{\{ customer_name \}\}, your order #\{\{ order_id \}\} is now ready for pickup! Thank you for choosing \{\{ restaurant_name \}\}."
)

# Order Preparing - Email
create_template(
  'order_preparing',
  'email',
  'Your \{\{ restaurant_name \}\} Order #\{\{ order_id \}\} is Being Prepared',
  <<~HTML
    <table width="100%" border="0" cellspacing="0" cellpadding="0"
           style="background-color: #f8f8f8; padding: 20px 0; font-family: Arial, sans-serif;">
      <tr>
        <td align="center">
          <table width="600" border="0" cellspacing="0" cellpadding="0"
                 style="background-color: #ffffff; border-radius: 6px; overflow: hidden;">
            
            <!-- HEADER -->
            <tr>
              <td align="center" style="background-color: #2196F3; padding: 20px;">
                <h1 style="margin: 0; font-size: 24px; color: #ffffff;
                           font-family: 'Helvetica Neue', Arial, sans-serif;">
                  Your Order is Being Prepared
                </h1>
              </td>
            </tr>

            <!-- SPACER -->
            <tr><td style="height: 20px;">&nbsp;</td></tr>

            <!-- MAIN CONTENT -->
            <tr>
              <td style="padding: 0 30px 20px;">
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Hi <strong>\{\{ customer_name \}\}</strong>,
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  We're excited to let you know that we've started preparing your order #\{\{ order_id \}\}.
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Estimated pickup time: <strong>\{\{ eta \}\}</strong>
                </p>

                <p style="margin: 0; color: #333; font-size: 16px; line-height: 24px;">
                  We will send you another notification when your order is ready for pickup.
                </p>
              </td>
            </tr>

            <!-- FOOTER -->
            <tr>
              <td style="padding: 20px 30px; background-color: #f2f2f2;
                         color: #555; font-size: 14px; line-height: 20px;
                         border-top: 1px solid #ddd;">
                <p style="margin: 0;">
                  <strong>\{\{ restaurant_name \}\}</strong><br/>
                  \{\{ restaurant_address \}\} | \{\{ restaurant_phone \}\}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  HTML
)

# Order Preparing - SMS
create_template(
  'order_preparing',
  'sms',
  nil,
  "Hi \{\{ customer_name \}\}, your order #\{\{ order_id \}\} is now being prepared! ETA: \{\{ eta \}\}."
)

# Reservation Confirmation - Email
create_template(
  'reservation_confirmation',
  'email',
  'Your \{\{ restaurant_name \}\} Reservation Confirmation',
  <<~HTML
    <table width="100%" border="0" cellspacing="0" cellpadding="0"
           style="background-color: #f8f8f8; padding: 20px 0; font-family: Arial, sans-serif;">
      <tr>
        <td align="center">
          <table width="600" border="0" cellspacing="0" cellpadding="0"
                 style="background-color: #ffffff; border-radius: 6px; overflow: hidden;">
            
            <!-- HEADER -->
            <tr>
              <td align="center" style="background-color: #9C27B0; padding: 20px;">
                <h1 style="margin: 0; font-size: 24px; color: #ffffff;
                           font-family: 'Helvetica Neue', Arial, sans-serif;">
                  Reservation Confirmation
                </h1>
              </td>
            </tr>

            <!-- SPACER -->
            <tr><td style="height: 20px;">&nbsp;</td></tr>

            <!-- MAIN CONTENT -->
            <tr>
              <td style="padding: 0 30px 20px;">
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Hi <strong>\{\{ contact_name \}\}</strong>,
                </p>

                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Thank you for booking a reservation at \{\{ restaurant_name \}\}. Here are your details:
                </p>

                <ul style="margin: 0 0 15px; padding: 0 0 0 20px; color: #333; font-size: 16px; line-height: 24px;">
                  <li>Reservation Date/Time: \{\{ reservation_time \}\}</li>
                  <li>Party Size: \{\{ party_size \}\}</li>
                  <li>Restaurant: \{\{ restaurant_name \}\}</li>
                  \{% if deposit_amount \%}
                  <li>Deposit Amount: $\{\{ deposit_amount \}\}</li>
                  \{% endif \%}
                </ul>

                <p style="margin: 0; color: #333; font-size: 16px; line-height: 24px;">
                  We look forward to serving you!
                </p>
              </td>
            </tr>

            <!-- FOOTER -->
            <tr>
              <td style="padding: 20px 30px; background-color: #f2f2f2;
                         color: #555; font-size: 14px; line-height: 20px;
                         border-top: 1px solid #ddd;">
                <p style="margin: 0;">
                  <strong>\{\{ restaurant_name \}\}</strong><br/>
                  \{\{ restaurant_address \}\} | \{\{ restaurant_phone \}\}
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  HTML
)

# Reservation Confirmation - SMS
create_template(
  'reservation_confirmation',
  'sms',
  nil,
  "Hi \{\{ contact_name \}\}, your \{\{ restaurant_name \}\} reservation is confirmed on \{\{ reservation_time \}\}. \{% if deposit_amount \%}Deposit amount: $\{\{ deposit_amount \}\}. \{% endif \%}We look forward to seeing you!"
)

puts "Created #{NotificationTemplate.count} notification templates."

#!/usr/bin/env ruby

t = NotificationTemplate.find_or_create_by(
  notification_type: 'reservation_confirmation',
  channel: 'email',
  restaurant_id: nil
)

t.update!(
  subject: 'Your {{ restaurant_name }} Reservation Confirmation #{{ reservation_id }}',
  content: <<~HTML
    <table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #f8f8f8; padding: 20px 0; font-family: Arial, sans-serif;">
      <tr>
        <td align="center">
          <table width="600" border="0" cellspacing="0" cellpadding="0" style="background-color: #ffffff; border-radius: 6px; overflow: hidden;">
            <tr>
              <td align="center" style="background-color: #c1902f; padding: 20px;">
                <h1 style="margin: 0; font-size: 24px; color: #ffffff; font-family: 'Helvetica Neue', Arial, sans-serif;">
                  {{ restaurant_name }} Reservation Confirmation
                </h1>
              </td>
            </tr>
            <tr><td style="height: 20px;">&nbsp;</td></tr>
            <tr>
              <td style="padding: 0 30px 20px;">
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Hi <strong>{{ customer_name }}</strong>,
                </p>
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  Your reservation has been confirmed! Below are your details:
                </p>
                <table width="100%" border="0" cellspacing="0" cellpadding="0" style="margin-bottom: 15px; font-size: 16px; color: #333;">
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Reservation ID:</strong> {{ reservation_id }}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Date:</strong> {{ reservation_date }}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Time:</strong> {{ reservation_time }}
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;">
                      <strong>Party Size:</strong> {{ party_size }} guests
                    </td>
                  </tr>
                </table>
                <p style="margin: 0 0 15px; color: #333; font-size: 16px; line-height: 24px;">
                  We'll contact you at <strong>{{ contact_phone }}</strong> if we have questions.
                </p>
                <p style="margin: 0; color: #333; font-size: 16px; line-height: 24px;">
                  We look forward to serving you!
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding: 20px 30px; background-color: #f2f2f2; color: #555; font-size: 14px; line-height: 20px; border-top: 1px solid #ddd;">
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

puts 'Created reservation confirmation Email template'

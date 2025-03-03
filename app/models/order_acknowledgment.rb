# app/models/order_acknowledgment.rb
class OrderAcknowledgment < ApplicationRecord
  belongs_to :order
  belongs_to :user
  
  validates :order_id, uniqueness: { scope: :user_id, message: "has already been acknowledged by this user" }
end

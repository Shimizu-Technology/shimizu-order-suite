class StoreCredit < ApplicationRecord
  belongs_to :order, optional: true
  
  validates :amount, numericality: { greater_than: 0 }
  validates :customer_email, presence: true
  
  before_create :set_remaining_amount
  
  scope :active, -> { where(status: 'active') }
  
  def use_credit(amount_to_use)
    return false if status != 'active' || amount_to_use > remaining_amount
    
    self.remaining_amount -= amount_to_use
    
    if remaining_amount <= 0
      self.status = 'used'
    end
    
    save
  end
  
  private
  
  def set_remaining_amount
    self.remaining_amount = self.amount if self.remaining_amount.nil?
  end
end

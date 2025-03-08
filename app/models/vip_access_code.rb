class VipAccessCode < ApplicationRecord
  default_scope { with_restaurant_scope }
  
  belongs_to :restaurant
  belongs_to :special_event, optional: true
  belongs_to :user, optional: true
  
  has_many :orders
  has_many :vip_code_recipients, dependent: :destroy
  
  validates :code, presence: true, uniqueness: { scope: :restaurant_id }
  
  scope :active, -> { where(is_active: true) }
  scope :available, -> { active.where("expires_at IS NULL OR expires_at > ?", Time.current).where("max_uses IS NULL OR current_uses < max_uses") }
  scope :by_group, ->(group_id) { where(group_id: group_id) }
  
  def available?
    is_active && (expires_at.nil? || expires_at > Time.current) &&
      (max_uses.nil? || current_uses < max_uses)
  end
  
  def use!
    increment!(:current_uses)
  end
end

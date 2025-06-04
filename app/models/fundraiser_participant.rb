# app/models/fundraiser_participant.rb

class FundraiserParticipant < ApplicationRecord
  # Associations
  belongs_to :fundraiser
  
  # Include IndirectTenantScoped for tenant isolation through fundraiser
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: :fundraiser, foreign_key: 'restaurant_id'
  
  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_team, ->(team) { where(team: team) if team.present? }
  
  # Methods
  def to_s
    name
  end
end

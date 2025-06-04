# app/serializers/fundraiser_participant_serializer.rb

class FundraiserParticipantSerializer < ActiveModel::Serializer
  attributes :id, :name, :team, :active, :created_at, :updated_at
  
  belongs_to :fundraiser
  
  def created_at
    object.created_at.iso8601 if object.created_at
  end
  
  def updated_at
    object.updated_at.iso8601 if object.updated_at
  end
end

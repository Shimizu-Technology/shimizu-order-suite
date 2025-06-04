# test/models/fundraiser_participant_test.rb
require "test_helper"

class FundraiserParticipantTest < ActiveSupport::TestCase
  setup do
    @fundraiser = fundraisers(:one)
    @participant = FundraiserParticipant.new(
      fundraiser: @fundraiser,
      name: "Test Participant",
      team: "Test Team",
      active: true
    )
  end

  test "should be valid with valid attributes" do
    assert @participant.valid?
  end

  test "should require a name" do
    @participant.name = nil
    assert_not @participant.valid?
    assert_includes @participant.errors[:name], "can't be blank"
  end

  test "should require a fundraiser" do
    @participant.fundraiser = nil
    assert_not @participant.valid?
    assert_includes @participant.errors[:fundraiser], "must exist"
  end

  test "active scope should return only active participants" do
    @participant.save!
    
    inactive_participant = FundraiserParticipant.create!(
      fundraiser: @fundraiser,
      name: "Inactive Participant",
      team: "Test Team",
      active: false
    )
    
    assert_includes FundraiserParticipant.active, @participant
    assert_not_includes FundraiserParticipant.active, inactive_participant
  end

  test "by_team scope should filter by team" do
    @participant.team = "Alpha Team"
    @participant.save!
    
    beta_participant = FundraiserParticipant.create!(
      fundraiser: @fundraiser,
      name: "Beta Participant",
      team: "Beta Team",
      active: true
    )
    
    assert_includes FundraiserParticipant.by_team("Alpha Team"), @participant
    assert_not_includes FundraiserParticipant.by_team("Alpha Team"), beta_participant
    
    # Should return all participants when no team is specified
    assert_includes FundraiserParticipant.by_team(nil), @participant
    assert_includes FundraiserParticipant.by_team(nil), beta_participant
  end

  test "should enforce tenant isolation through fundraiser" do
    @participant.save!
    
    # Set current restaurant
    restaurant = @fundraiser.restaurant
    ApplicationRecord.current_restaurant = restaurant
    
    # Should find participant for current restaurant
    assert_includes FundraiserParticipant.all, @participant
    
    # Change current restaurant
    another_restaurant = restaurants(:two)
    ApplicationRecord.current_restaurant = another_restaurant
    
    # Should not find participant for different restaurant
    assert_not_includes FundraiserParticipant.all, @participant
    
    # Reset current restaurant
    ApplicationRecord.current_restaurant = nil
  end
end

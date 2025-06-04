# test/models/fundraiser_test.rb
require "test_helper"

class FundraiserTest < ActiveSupport::TestCase
  setup do
    @restaurant = restaurants(:one)
    @fundraiser = Fundraiser.new(
      restaurant: @restaurant,
      name: "Test Fundraiser",
      slug: "test-fundraiser",
      description: "A test fundraiser",
      active: false
    )
  end

  test "should be valid with valid attributes" do
    assert @fundraiser.valid?
  end

  test "should require a name" do
    @fundraiser.name = nil
    assert_not @fundraiser.valid?
    assert_includes @fundraiser.errors[:name], "can't be blank"
  end

  test "should require a slug" do
    @fundraiser.slug = nil
    assert_not @fundraiser.valid?
    assert_includes @fundraiser.errors[:slug], "can't be blank"
  end

  test "should require a unique slug within restaurant scope" do
    @fundraiser.save!
    
    duplicate = Fundraiser.new(
      restaurant: @restaurant,
      name: "Another Fundraiser",
      slug: "test-fundraiser",
      description: "Another test fundraiser"
    )
    
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
    
    # Should be valid with same slug but different restaurant
    another_restaurant = restaurants(:two)
    duplicate.restaurant = another_restaurant
    assert duplicate.valid?
  end

  test "should normalize slug" do
    @fundraiser.slug = "Test Slug"
    @fundraiser.valid?
    assert_equal "test-slug", @fundraiser.slug
  end

  test "should validate slug format" do
    invalid_slugs = ["test slug", "TEST", "test@slug", "test.slug"]
    
    invalid_slugs.each do |slug|
      @fundraiser.slug = slug
      assert_not @fundraiser.valid?
      assert_includes @fundraiser.errors[:slug], "only allows lowercase letters, numbers, hyphens, and underscores"
    end
    
    valid_slugs = ["test-slug", "test_slug", "test123", "t"]
    
    valid_slugs.each do |slug|
      @fundraiser.slug = slug
      assert @fundraiser.valid?, "#{slug} should be valid"
    end
  end

  test "active scope should return only active fundraisers" do
    @fundraiser.save!
    
    active_fundraiser = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Active Fundraiser",
      slug: "active-fundraiser",
      active: true
    )
    
    assert_includes Fundraiser.active, active_fundraiser
    assert_not_includes Fundraiser.active, @fundraiser
  end

  test "current scope should return active fundraisers within date range" do
    now = Time.current
    
    # Active fundraiser with no dates (always current)
    always_current = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Always Current",
      slug: "always-current",
      active: true
    )
    
    # Active fundraiser with future end date
    current_with_end = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Current with End",
      slug: "current-with-end",
      active: true,
      end_date: now + 1.day
    )
    
    # Active fundraiser with past start date
    current_with_start = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Current with Start",
      slug: "current-with-start",
      active: true,
      start_date: now - 1.day
    )
    
    # Active fundraiser with start and end dates (current)
    current_with_range = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Current with Range",
      slug: "current-with-range",
      active: true,
      start_date: now - 1.day,
      end_date: now + 1.day
    )
    
    # Active fundraiser with future start date (not current)
    future = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Future",
      slug: "future",
      active: true,
      start_date: now + 1.day
    )
    
    # Active fundraiser with past end date (not current)
    past = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Past",
      slug: "past",
      active: true,
      end_date: now - 1.day
    )
    
    # Inactive fundraiser within date range (not current)
    inactive = Fundraiser.create!(
      restaurant: @restaurant,
      name: "Inactive",
      slug: "inactive",
      active: false,
      start_date: now - 1.day,
      end_date: now + 1.day
    )
    
    current_fundraisers = Fundraiser.current
    
    assert_includes current_fundraisers, always_current
    assert_includes current_fundraisers, current_with_end
    assert_includes current_fundraisers, current_with_start
    assert_includes current_fundraisers, current_with_range
    
    assert_not_includes current_fundraisers, future
    assert_not_includes current_fundraisers, past
    assert_not_includes current_fundraisers, inactive
  end

  test "should enforce tenant isolation" do
    @fundraiser.save!
    
    # Set current restaurant
    ApplicationRecord.current_restaurant = @restaurant
    
    # Should find fundraiser for current restaurant
    assert_includes Fundraiser.all, @fundraiser
    
    # Change current restaurant
    another_restaurant = restaurants(:two)
    ApplicationRecord.current_restaurant = another_restaurant
    
    # Should not find fundraiser for different restaurant
    assert_not_includes Fundraiser.all, @fundraiser
    
    # Reset current restaurant
    ApplicationRecord.current_restaurant = nil
  end
end

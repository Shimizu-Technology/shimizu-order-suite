# test/models/fundraiser_item_test.rb
require "test_helper"

class FundraiserItemTest < ActiveSupport::TestCase
  setup do
    @fundraiser = fundraisers(:one)
    @item = FundraiserItem.new(
      fundraiser: @fundraiser,
      name: "Test Item",
      description: "A test item for fundraising",
      price: 15.99,
      image_url: "https://example.com/test.jpg",
      active: true,
      stock_quantity: 50,
      enable_stock_tracking: true,
      low_stock_threshold: 10
    )
  end

  test "should be valid with valid attributes" do
    assert @item.valid?
  end

  test "should require a name" do
    @item.name = nil
    assert_not @item.valid?
    assert_includes @item.errors[:name], "can't be blank"
  end

  test "should require a fundraiser" do
    @item.fundraiser = nil
    assert_not @item.valid?
    assert_includes @item.errors[:fundraiser], "must exist"
  end

  test "should require a non-negative price" do
    @item.price = -1
    assert_not @item.valid?
    assert_includes @item.errors[:price], "must be greater than or equal to 0"
    
    @item.price = 0
    assert @item.valid?
  end

  test "should require a non-negative stock quantity when tracking is enabled" do
    @item.stock_quantity = -1
    assert_not @item.valid?
    assert_includes @item.errors[:stock_quantity], "must be greater than or equal to 0"
    
    @item.stock_quantity = 0
    assert @item.valid?
  end

  test "should require a positive low stock threshold when tracking is enabled" do
    @item.low_stock_threshold = 0
    assert_not @item.valid?
    assert_includes @item.errors[:low_stock_threshold], "must be greater than or equal to 1"
    
    @item.low_stock_threshold = 1
    assert @item.valid?
  end

  test "active scope should return only active items" do
    @item.save!
    
    inactive_item = FundraiserItem.create!(
      fundraiser: @fundraiser,
      name: "Inactive Item",
      price: 9.99,
      active: false
    )
    
    assert_includes FundraiserItem.active, @item
    assert_not_includes FundraiserItem.active, inactive_item
  end

  test "should reset inventory fields when tracking is disabled" do
    @item.enable_stock_tracking = false
    @item.save!
    
    assert_nil @item.reload.stock_quantity
    assert_nil @item.reload.low_stock_threshold
  end

  test "available_quantity should return nil when tracking is disabled" do
    @item.enable_stock_tracking = false
    assert_nil @item.available_quantity
  end

  test "available_quantity should return stock_quantity when tracking is enabled" do
    @item.stock_quantity = 42
    assert_equal 42, @item.available_quantity
  end

  test "low_stock? should return false when tracking is disabled" do
    @item.enable_stock_tracking = false
    assert_not @item.low_stock?
  end

  test "low_stock? should return true when stock is below threshold" do
    @item.stock_quantity = 5
    @item.low_stock_threshold = 10
    assert @item.low_stock?
    
    @item.stock_quantity = 10
    assert @item.low_stock?
    
    @item.stock_quantity = 11
    assert_not @item.low_stock?
  end

  test "out_of_stock? should return false when tracking is disabled" do
    @item.enable_stock_tracking = false
    assert_not @item.out_of_stock?
  end

  test "out_of_stock? should return true when stock is zero or less" do
    @item.stock_quantity = 0
    assert @item.out_of_stock?
    
    @item.stock_quantity = 1
    assert_not @item.out_of_stock?
  end

  test "update_stock should adjust stock quantity" do
    @item.stock_quantity = 10
    @item.save!
    
    @item.update_stock(5)
    assert_equal 15, @item.reload.stock_quantity
    
    @item.update_stock(-8)
    assert_equal 7, @item.reload.stock_quantity
  end

  test "update_stock should not allow negative stock" do
    @item.stock_quantity = 10
    @item.save!
    
    @item.update_stock(-15)
    assert_equal 0, @item.reload.stock_quantity
  end

  test "update_stock should do nothing when tracking is disabled" do
    @item.enable_stock_tracking = false
    @item.stock_quantity = nil
    @item.save!
    
    @item.update_stock(5)
    assert_nil @item.reload.stock_quantity
  end

  test "should enforce tenant isolation through fundraiser" do
    @item.save!
    
    # Set current restaurant
    restaurant = @fundraiser.restaurant
    ApplicationRecord.current_restaurant = restaurant
    
    # Should find item for current restaurant
    assert_includes FundraiserItem.all, @item
    
    # Change current restaurant
    another_restaurant = restaurants(:two)
    ApplicationRecord.current_restaurant = another_restaurant
    
    # Should not find item for different restaurant
    assert_not_includes FundraiserItem.all, @item
    
    # Reset current restaurant
    ApplicationRecord.current_restaurant = nil
  end
end

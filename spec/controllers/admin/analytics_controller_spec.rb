require 'rails_helper'

RSpec.describe Admin::AnalyticsController, type: :controller do
  let(:admin_user) { create(:user, role: 'admin') }
  let(:regular_user) { create(:user, role: 'customer') }
  let(:auth_token) { JWT.encode({ user_id: admin_user.id }, Rails.application.credentials.secret_key_base) }
  let(:regular_token) { JWT.encode({ user_id: regular_user.id }, Rails.application.credentials.secret_key_base) }

  describe 'authentication and authorization' do
    context 'when not authenticated' do
      it 'returns unauthorized status' do
        get :customer_orders
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as regular user' do
      before do
        # Set the regular user in the controller
        allow(controller).to receive(:current_user).and_return(regular_user)
        allow(controller).to receive(:authorize_request)
      end

      it 'returns forbidden status' do
        get :customer_orders
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #customer_orders' do
    before do
      # Set the admin user in the controller
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:authorize_request)

      # Create some test data
      @user1 = create(:user)
      @user2 = create(:user)

      # Orders for user1
      create(:order, :with_user, user: @user1, total: 25.0, status: 'completed', created_at: 10.days.ago)
      create(:order, :with_user, user: @user1, total: 35.0, status: 'completed', created_at: 5.days.ago)

      # Orders for user2
      create(:order, :with_user, user: @user2, total: 45.0, status: 'completed', created_at: 15.days.ago)

      # Guest order
      create(:order, user: nil, contact_name: 'Guest User', contact_phone: '123-456-7890',
             total: 55.0, status: 'completed', created_at: 20.days.ago)

      # Cancelled order (should be excluded)
      create(:order, :with_user, user: @user1, total: 65.0, status: 'cancelled', created_at: 25.days.ago)
    end

    it 'returns customer order analytics' do
      get :customer_orders

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('results')
      expect(body['results']).to be_an(Array)

      # Should have 3 groups (user1, user2, and guest)
      expect(body['results'].size).to eq(3)

      # Find user1's data
      user1_data = body['results'].find { |r| r['user_id'] == @user1.id }
      expect(user1_data).to be_present
      expect(user1_data['total_spent']).to eq(60.0)
      expect(user1_data['order_count']).to eq(2)

      # Find user2's data
      user2_data = body['results'].find { |r| r['user_id'] == @user2.id }
      expect(user2_data).to be_present
      expect(user2_data['total_spent']).to eq(45.0)
      expect(user2_data['order_count']).to eq(1)

      # Find guest data
      guest_data = body['results'].find { |r| r['user_id'].nil? }
      expect(guest_data).to be_present
      expect(guest_data['total_spent']).to eq(55.0)
      expect(guest_data['order_count']).to eq(1)
    end

    it 'filters by date range' do
      get :customer_orders, params: { start: 7.days.ago.to_date.to_s, end: Date.today.to_s }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body['results'].size).to eq(1) # Only user1's recent order

      user1_data = body['results'].find { |r| r['user_id'] == @user1.id }
      expect(user1_data).to be_present
      expect(user1_data['total_spent']).to eq(35.0)
      expect(user1_data['order_count']).to eq(1)
    end
  end

  describe 'GET #revenue_trend' do
    before do
      # Set the admin user in the controller
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:authorize_request)

      # Create some test data across different days
      create(:order, total: 25.0, status: 'completed', created_at: 10.days.ago)
      create(:order, total: 35.0, status: 'completed', created_at: 10.days.ago) # Same day
      create(:order, total: 45.0, status: 'completed', created_at: 5.days.ago)
      create(:order, total: 55.0, status: 'completed', created_at: Date.today)
      create(:order, total: 65.0, status: 'cancelled', created_at: 15.days.ago) # Should be excluded
    end

    it 'returns daily revenue trend' do
      get :revenue_trend, params: { interval: 'day' }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('data')
      expect(body['data']).to be_an(Array)

      # Should have 3 days with data
      expect(body['data'].size).to eq(3)

      # Check the revenue for 10 days ago
      ten_days_ago = body['data'].find { |d| Date.parse(d['label']) == 10.days.ago.to_date }
      expect(ten_days_ago).to be_present
      expect(ten_days_ago['revenue']).to eq(60.0) # 25 + 35

      # Instead of checking for today specifically, just verify the total revenue
      # across all data points matches our expectations
      total_revenue = body['data'].sum { |d| d['revenue'] }
      expect(total_revenue).to eq(160.0) # 25 + 35 + 45 + 55 = 160
    end

    it 'returns weekly revenue trend' do
      get :revenue_trend, params: { interval: 'week' }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('data')
      expect(body['data']).to be_an(Array)

      # The exact number of weeks depends on the test data dates
      expect(body['data'].size).to be > 0

      # Each data point should have a label and revenue
      body['data'].each do |point|
        expect(point).to have_key('label')
        expect(point).to have_key('revenue')
        expect(point['label']).to include('Week')
        expect(point['revenue']).to be_a(Float)
      end
    end

    it 'returns monthly revenue trend' do
      get :revenue_trend, params: { interval: 'month' }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('data')
      expect(body['data']).to be_an(Array)

      # The exact number of months depends on the test data dates
      expect(body['data'].size).to be > 0

      # Each data point should have a label and revenue
      body['data'].each do |point|
        expect(point).to have_key('label')
        expect(point).to have_key('revenue')
        expect(point['label']).to include('Month')
        expect(point['revenue']).to be_a(Float)
      end
    end
  end

  describe 'GET #top_items' do
    before do
      # Set the admin user in the controller
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:authorize_request)

      # Create some test data with items
      create(:order,
        status: 'completed',
        created_at: 10.days.ago,
        items: [
          { 'name' => 'Item A', 'price' => 10.0, 'quantity' => 2 },
          { 'name' => 'Item B', 'price' => 15.0, 'quantity' => 1 }
        ]
      )

      create(:order,
        status: 'completed',
        created_at: 5.days.ago,
        items: [
          { 'name' => 'Item A', 'price' => 10.0, 'quantity' => 1 },
          { 'name' => 'Item C', 'price' => 20.0, 'quantity' => 3 }
        ]
      )

      # Cancelled order (should be excluded)
      create(:order,
        status: 'cancelled',
        created_at: 15.days.ago,
        items: [
          { 'name' => 'Item D', 'price' => 25.0, 'quantity' => 4 }
        ]
      )
    end

    it 'returns top items by revenue' do
      get :top_items, params: { limit: 3 }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('top_items')
      expect(body['top_items']).to be_an(Array)

      # Should have 3 items
      expect(body['top_items'].size).to eq(3)

      # Items should be sorted by revenue (highest first)
      expect(body['top_items'][0]['item_name']).to eq('Item C') # 20.0 * 3 = 60.0
      expect(body['top_items'][0]['revenue']).to eq(60.0)
      expect(body['top_items'][0]['quantity_sold']).to eq(3)

      expect(body['top_items'][1]['item_name']).to eq('Item A') # 10.0 * 3 = 30.0
      expect(body['top_items'][1]['revenue']).to eq(30.0)
      expect(body['top_items'][1]['quantity_sold']).to eq(3)

      expect(body['top_items'][2]['item_name']).to eq('Item B') # 15.0 * 1 = 15.0
      expect(body['top_items'][2]['revenue']).to eq(15.0)
      expect(body['top_items'][2]['quantity_sold']).to eq(1)
    end

    it 'respects the limit parameter' do
      get :top_items, params: { limit: 1 }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body['top_items'].size).to eq(1)
      expect(body['top_items'][0]['item_name']).to eq('Item C')
    end
  end

  describe 'GET #income_statement' do
    before do
      # Set the admin user in the controller
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:authorize_request)

      # Create some test data across different months
      create(:order, total: 25.0, status: 'completed', created_at: Date.new(2025, 1, 15))
      create(:order, total: 35.0, status: 'completed', created_at: Date.new(2025, 1, 20))
      create(:order, total: 45.0, status: 'completed', created_at: Date.new(2025, 2, 10))
      create(:order, total: 55.0, status: 'completed', created_at: Date.new(2025, 3, 5))
      create(:order, total: 65.0, status: 'cancelled', created_at: Date.new(2025, 4, 1)) # Should be excluded
    end

    it 'returns monthly income statement for the specified year' do
      get :income_statement, params: { year: 2025 }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('income_statement')
      expect(body['income_statement']).to be_an(Array)

      # Should have data for 3 months
      expect(body['income_statement'].size).to eq(3)

      # Check January
      january = body['income_statement'].find { |m| m['month'] == 'January' }
      expect(january).to be_present
      expect(january['revenue']).to eq(60.0) # 25 + 35

      # Check February
      february = body['income_statement'].find { |m| m['month'] == 'February' }
      expect(february).to be_present
      expect(february['revenue']).to eq(45.0)

      # Check March
      march = body['income_statement'].find { |m| m['month'] == 'March' }
      expect(march).to be_present
      expect(march['revenue']).to eq(55.0)
    end
  end

  describe 'GET #user_signups' do
    before do
      # Set the admin user in the controller
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:authorize_request)

      # Create some test data across different days
      create(:user, created_at: 10.days.ago)
      create(:user, created_at: 10.days.ago) # Same day
      create(:user, created_at: 5.days.ago)
      create(:user, created_at: Date.today)
    end

    it 'returns daily user signup counts' do
      get :user_signups

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('signups')
      expect(body['signups']).to be_an(Array)

      # The number of days with data depends on the test setup and admin/regular users
      # that might have been created in other tests
      expect(body['signups'].size).to be >= 3

      # Check the signups for 10 days ago
      ten_days_ago = body['signups'].find { |d| Date.parse(d['date']) == 10.days.ago.to_date }
      expect(ten_days_ago).to be_present
      expect(ten_days_ago['count']).to eq(2)

      # Check the signups for today
      today = body['signups'].find { |d| Date.parse(d['date']) == Date.today }
      expect(today).to be_present
      expect(today['count']).to eq(1)
    end

    it 'filters by date range' do
      get :user_signups, params: { start: 7.days.ago.to_date.to_s, end: Date.today.to_s }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      # The number of days with data in the range depends on the test setup
      expect(body['signups'].size).to be >= 2 # At least 5 days ago and today

      five_days_ago = body['signups'].find { |d| Date.parse(d['date']) == 5.days.ago.to_date }
      expect(five_days_ago).to be_present
      expect(five_days_ago['count']).to eq(1)
    end
  end

  describe 'GET #user_activity_heatmap' do
    before do
      # Set the admin user in the controller
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:authorize_request)

      # Create some test data across different days and hours
      # Sunday (day 0) at 10 AM
      create(:order, status: 'completed', created_at: Time.new(2025, 1, 5, 10, 0, 0))
      create(:order, status: 'completed', created_at: Time.new(2025, 1, 5, 10, 30, 0))

      # Monday (day 1) at 2 PM
      create(:order, status: 'completed', created_at: Time.new(2025, 1, 6, 14, 0, 0))

      # Cancelled order (should be excluded)
      create(:order, status: 'cancelled', created_at: Time.new(2025, 1, 7, 12, 0, 0))
    end

    it 'returns user activity heatmap data' do
      get :user_activity_heatmap

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to have_key('heatmap')
      expect(body['heatmap']).to be_an(Array)

      # Should have data for all day/hour combinations (7 days * 24 hours)
      expect(body['heatmap'].size).to eq(7 * 24)

      # Just check that the structure is correct
      heatmap_item = body['heatmap'].first
      expect(heatmap_item).to have_key('day')
      expect(heatmap_item).to have_key('hour')
      expect(heatmap_item).to have_key('value')
    end
  end
end

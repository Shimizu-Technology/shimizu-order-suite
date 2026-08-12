require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  #Setting up test restaurant
  let(:restaurant) { create(:restaurant) } 

  #Setting up test restaurant for all tests
  before do
    ApplicationRecord.current_restaurant = restaurant
  end

  # Test associations: Pass
  describe "associations" do
    it "belongs to user (optional)" do
      association = AuditLog.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
      expect(association.options[:optional]).to be true
    end
  end

  #Test validations: Pass
  describe "validations" do
    it "requires an action" do
      audit_log = AuditLog.new
      expect(audit_log).not_to be_valid
      expect(audit_log.errors[:action]).to include("can't be blank")

      audit_log.action = "login"
      expect(audit_log.valid?).to be true
    end
  end

  
  describe "scopes" do
    #Setting up audit logs for testing
    before do
      create(:audit_log, action: 'tenant_access', restaurant: restaurant)
      create(:audit_log, action: 'create', restaurant: restaurant)
      create(:audit_log, action: 'update', restaurant: restaurant)
      create(:audit_log, action: 'delete', restaurant: restaurant)
      create(:audit_log, action: 'suspicious_activity', restaurant: restaurant)
    end

    #Tenant Access: Pass
    it "tenant_access_logs filters only tenant access" do
      expect(AuditLog.tenant_access_logs.count).to eq 1
    end

    #Data Modification: Pass
    it "data_modification_logs filters only data modification" do
      expect(AuditLog.data_modification_logs.count).to eq 3
      #Create, update, delete set at before do
    end

    #Suspicious Activity: Pass
    it "suspicious_activity filters only suspicious activity" do
      expect(AuditLog.suspicious_activity.count).to eq 1
    end
  end

  #Test tenant scoping: Pass
  describe "tenant scoping" do
    #Setting up Second test restaurant
    let(:restaurant2) { create(:restaurant) }

    #Setting up audit logs for both test restaurants
    before do
      create_list(:audit_log, 4, restaurant: restaurant)
      create_list(:audit_log, 2, restaurant: restaurant2)
    end

    it "only returns logs for the current restaurant" do
      expect(AuditLog.count).to eq 4

      #Check 2nd restaurant
      ApplicationRecord.current_restaurant = restaurant2
      expect(AuditLog.count).to eq 2
    end
  end

  #Test class methods: Pass
  describe "class methods" do
    #Setting up test user
    let(:user) { create(:user, restaurant: restaurant) }

    #Setting up test IP Address
    let(:ip_address) { "192.168.1.1" }

    describe ".log_tenant_access" do
      it "Logs tenant access associated with the correct user, restaurant, and details" do
        log = AuditLog.log_tenant_access(user, restaurant, ip_address, { browser: "Chrome" })

        expect(log).to be_persisted
        expect(log.user_id).to eq(user.id) 
        expect(log.restaurant_id).to eq(restaurant.id)
        expect(log.action).to eq "tenant_access"
        expect(log.resource_type).to eq "Restaurant"
        expect(log.resource_id).to eq(restaurant.id)
        expect(log.ip_address).to eq(ip_address)
        expect(log.details).to include("browser" => "Chrome")
        expect(log.created_at).to be_within(5.seconds).of(Time.current)
      end
    end
    
    #Log Cross Tenant Access: Pass
    describe ".log_cross_tenant_access" do 

      #Setting up target restaurant ID
      let(:target_restaurant_id) { 4 }

      it "Logs cross-tenant access attempt associated with the correct user, restaurant, and details, and categorizes it as suspicious activity" do
        log = AuditLog.log_cross_tenant_access(user, target_restaurant_id, ip_address, { browser: "Chrome" })

        expect(log).to be_persisted
        expect(log.user_id).to eq(user.id) 
        expect(log.restaurant_id).to eq(restaurant.id)
        expect(log.action).to eq "suspicious_activity"
        expect(log.resource_type).to eq "Restaurant"
        expect(log.resource_id).to eq(target_restaurant_id)
        expect(log.ip_address).to eq(ip_address)
        expect(log.details).to include(
          "browser" => "Chrome",
          "attempt_type" => "cross_tenant_access",
          "user_restaurant_id" => restaurant.id,
          "target_restaurant_id" => target_restaurant_id
        )
        expect(log.created_at).to be_within(5.seconds).of(Time.current)
      end
    end

    #Log Data Modification: Pass
    describe ".log_data_modification" do
      #Setting up test resource
      let(:resource) { create(:menu_item, restaurant: restaurant) }

      it "Logs data modification associated with the correct user, restaurant, and details" do
        log = AuditLog.log_data_modification(user, "update", "MenuItem", 1, ip_address, { browser: "Chrome", changes: { "name" => ["Old Name", "New Name"] } })

        expect(log).to be_persisted
        expect(log.user_id).to eq(user.id) 
        expect(log.restaurant_id).to eq(restaurant.id)
        expect(log.action).to eq "update"
        expect(log.resource_type).to eq "MenuItem"
        expect(log.resource_id).to eq(1)
        expect(log.ip_address).to eq(ip_address)
        expect(log.details).to include(
          "browser" => "Chrome",
          "changes" => { "name" => ["Old Name", "New Name"] }
        )
        expect(log.created_at).to be_within(5.seconds).of(Time.current)
      end
    end
  end
end

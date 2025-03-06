require 'rails_helper'

RSpec.describe VipCodeGenerator do
  let(:restaurant) { create(:restaurant) }
  let(:special_event) { create(:special_event, restaurant: restaurant, code_prefix: "TEST") }
  
  describe '.generate_individual_codes' do
    it 'creates the specified number of individual VIP codes' do
      expect {
        VipCodeGenerator.generate_individual_codes(special_event, 5)
      }.to change(VipAccessCode, :count).by(5)
    end
    
    it 'creates codes with the correct attributes' do
      codes = VipCodeGenerator.generate_individual_codes(special_event, 3, { name: "Test Individual" })
      
      expect(codes.length).to eq(3)
      codes.each do |code|
        expect(code.special_event).to eq(special_event)
        expect(code.restaurant).to eq(restaurant)
        expect(code.name).to eq("Test Individual")
        expect(code.max_uses).to eq(1)
        expect(code.current_uses).to eq(0)
        expect(code.is_active).to be true
        expect(code.code).to match(/^TEST-[A-Z]{4}-\d{4}$/)
      end
    end
    
    it 'uses default name when not provided' do
      codes = VipCodeGenerator.generate_individual_codes(special_event, 1)
      expect(codes.first.name).to eq("Individual VIP")
    end
  end
  
  describe '.generate_group_code' do
    it 'creates a single group VIP code' do
      expect {
        VipCodeGenerator.generate_group_code(special_event)
      }.to change(VipAccessCode, :count).by(1)
    end
    
    it 'creates a code with the correct attributes' do
      code = VipCodeGenerator.generate_group_code(special_event, { 
        name: "Test Group", 
        max_uses: 20 
      })
      
      expect(code.special_event).to eq(special_event)
      expect(code.restaurant).to eq(restaurant)
      expect(code.name).to eq("Test Group")
      expect(code.max_uses).to eq(20)
      expect(code.current_uses).to eq(0)
      expect(code.is_active).to be true
      expect(code.code).to match(/^TEST-[A-Z]{4}-\d{4}$/)
      expect(code.group_id).not_to be_nil
    end
    
    it 'uses default name when not provided' do
      code = VipCodeGenerator.generate_group_code(special_event)
      expect(code.name).to eq("Group VIP")
    end
    
    it 'uses nil max_uses when not provided' do
      code = VipCodeGenerator.generate_group_code(special_event)
      expect(code.max_uses).to be_nil
    end
  end
  
  describe '.new_unique_code' do
    it 'generates a code with the event prefix' do
      allow(VipAccessCode).to receive(:exists?).and_return(false)
      code = VipCodeGenerator.send(:new_unique_code, special_event)
      expect(code).to match(/^TEST-[A-Z]{4}-\d{4}$/)
    end
    
    it 'uses VIP as default prefix when event has no prefix' do
      special_event.code_prefix = nil
      allow(VipAccessCode).to receive(:exists?).and_return(false)
      code = VipCodeGenerator.send(:new_unique_code, special_event)
      expect(code).to match(/^VIP-[A-Z]{4}-\d{4}$/)
    end
    
    it 'retries if code already exists' do
      # First call returns true (code exists), second call returns false (code doesn't exist)
      allow(VipAccessCode).to receive(:exists?).and_return(true, false)
      
      # Should make two attempts to generate a code
      expect(VipCodeGenerator).to receive(:new_unique_code).and_call_original
      
      code = VipCodeGenerator.send(:new_unique_code, special_event)
      expect(code).to match(/^TEST-[A-Z]{4}-\d{4}$/)
    end
  end
end

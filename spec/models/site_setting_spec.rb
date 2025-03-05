require 'rails_helper'

RSpec.describe SiteSetting, type: :model do
  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:site_setting)).to be_valid
    end
  end

  describe 'attributes' do
    it 'has hero_image_url attribute' do
      setting = SiteSetting.new(hero_image_url: 'https://example.com/hero.jpg')
      expect(setting.hero_image_url).to eq('https://example.com/hero.jpg')
    end

    it 'has spinner_image_url attribute' do
      setting = SiteSetting.new(spinner_image_url: 'https://example.com/spinner.gif')
      expect(setting.spinner_image_url).to eq('https://example.com/spinner.gif')
    end
  end

  describe 'singleton behavior' do
    it 'creates a new record if none exists' do
      expect {
        SiteSetting.first_or_create!
      }.to change(SiteSetting, :count).by(1)
    end

    it 'returns existing record if one exists' do
      existing = create(:site_setting)
      
      expect {
        result = SiteSetting.first_or_create!
        expect(result.id).to eq(existing.id)
      }.not_to change(SiteSetting, :count)
    end
  end

  # If you add validations to the model, you should test them here
  # For example:
  # describe 'validations' do
  #   it 'validates format of hero_image_url' do
  #     setting = build(:site_setting, hero_image_url: 'invalid-url')
  #     expect(setting).not_to be_valid
  #     expect(setting.errors[:hero_image_url]).to include('is not a valid URL')
  #   end
  # end
end

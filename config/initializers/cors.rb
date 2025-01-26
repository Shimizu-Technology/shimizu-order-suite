# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch('https://hafaloha-reservations.netlify.app', 'http://localhost:5173')

    resource '*',
      headers: :any,
      expose: %w[Authorization],
      methods: %i[get post put patch delete options head]
  end
end

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins lambda { |source, env|
      request_origin = env["HTTP_ORIGIN"]

      # Always allow localhost for development
      return true if request_origin == "http://localhost:5173"

      # Check if origin is allowed for any restaurant
      Restaurant.where("allowed_origins @> ARRAY[?]::varchar[]", [ request_origin ]).exists?
    }

    resource "*",
      headers: :any,
      expose: %w[Authorization],
      methods: %i[get post put patch delete options head],
      credentials: true,
      allow_headers: %w[Authorization Accept Content-Type Origin]
  end

  # For backward compatibility, keep the original origins
  allow do
    origins "https://hafaloha.netlify.app", "https://hafaloha-lvmt0.kinsta.page", "https://hafaloha-orders.com"

    resource "*",
      headers: :any,
      expose: %w[Authorization],
      methods: %i[get post put patch delete options head],
      credentials: true,
      allow_headers: %w[Authorization Accept Content-Type Origin]
  end
end

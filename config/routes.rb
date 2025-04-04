# config/routes.rb

Rails.application.routes.draw do
  # Mount Action Cable server
  mount ActionCable.server => '/cable'
  # Health check endpoints
  get "/health/check", to: "health#index"
  get "/health/sidekiq", to: "health#sidekiq_stats"
  # Authentication
  post "/signup", to: "users#create"
  post "/login",  to: "sessions#create"

  # Phone verification
  post "/verify_phone", to: "users#verify_phone"
  post "/resend_code",  to: "users#resend_code"
  
  # User management (for staff assignment)
  get "/users", to: "users#index"
  get "/users/:id", to: "users#show"

  # Password resets
  post  "/password/forgot", to: "passwords#forgot"
  patch "/password/reset",  to: "passwords#reset"

  # Staff Members and House Account routes
  resources :staff_members do
    member do
      get :transactions
      post :transactions, to: 'staff_members#add_transaction'
    end
  end
  
  # Reports routes
  namespace :reports do
    get 'house_account_balances'
    get 'staff_orders'
    get 'discount_summary'
    get 'house_account_activity/:staff_id', to: 'reports#house_account_activity', as: 'house_account_activity'
  end

  # Standard REST resources
  resources :restaurants, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      patch :toggle_vip_mode
      patch :set_current_event
    end

    resources :vip_access, only: [] do
      collection do
        post :validate_code
      end
    end
  end

  # VIP Access routes
  resources :vip_access, only: [] do
    collection do
      get :codes
      get :search_by_email
      post :generate_codes
      post :send_code_email
      post :bulk_send_vip_codes
      post :send_existing_vip_codes
    end
  end

  # VIP Access Codes routes
  delete "/vip_access/codes/:id", to: "vip_access#deactivate_code"
  patch "/vip_access/codes/:id", to: "vip_access#update_code"
  post "/vip_access/codes/:id/archive", to: "vip_access#archive_code"
  get "/vip_access/codes/:id/usage", to: "vip_access#code_usage"
  resources :seat_sections, only: [ :index, :show, :create, :update, :destroy ]

  resources :seats, only: [ :index, :show, :create, :update, :destroy ] do
    collection do
      post :bulk_update
    end
  end

  resources :reservations, only: [ :index, :show, :create, :update, :destroy ]
  resources :waitlist_entries, only: [ :index, :show, :create, :update, :destroy ]

  resources :seat_allocations, only: [ :index, :create, :update, :destroy ] do
    collection do
      post :multi_create
      post :reserve
      post :arrive
      post :no_show
      post :cancel
      post :finish
    end
  end

  resources :menus, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      post :set_active
      post :clone
    end
    
    # Nest categories under menus
    resources :categories, only: [ :index, :create, :update, :destroy ]
  end
  resources :menu_items, only: [ :index, :show, :create, :update, :destroy ]
  resources :notifications, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      post :acknowledge
      post :take_action
    end

    collection do
      get :unacknowledged
      post :acknowledge_all
    end
  end

  # Layouts
  resources :layouts, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      post :activate
    end
  end

  # Availability
  get "/availability", to: "availability#index"

  # -------------------------
  # PUBLIC categories endpoint (for backward compatibility)
  # -------------------------
  resources :categories, only: [ :index ]

  # -------------------------
  # Admin namespace
  # -------------------------
  namespace :admin do
    # Restaurant settings
    resource :settings, only: [ :show, :update ]

    # Site settings (hero/spinner)
    resource :site_settings, only: [ :show, :update ]

    # Operating Hours
    resources :operating_hours, only: [ :index, :update ]

    # Special Events
    resources :special_events, only: [ :index, :show, :create, :update, :destroy ] do
      resources :vip_access_codes, shallow: true
    end

    # Admin categories => for create/update/delete
    resources :categories, only: [ :index, :create, :update, :destroy ]

    # Admin analytics
    get "analytics/customer_orders",    to: "analytics#customer_orders"
    get "analytics/revenue_trend",     to: "analytics#revenue_trend"
    get "analytics/top_items",         to: "analytics#top_items"
    get "analytics/income_statement",  to: "analytics#income_statement"
    get "analytics/user_signups",      to: "analytics#user_signups"
    get "analytics/user_activity_heatmap", to: "analytics#user_activity_heatmap"
    
    # VIP Reports
    get "reports/menu_items",         to: "reports#menu_items"
    get "reports/payment_methods",     to: "reports#payment_methods"
    get "reports/vip_customers",      to: "reports#vip_customers"
    
    # System utilities
    post "test_sms", to: "system#test_sms"
    post "test_pushover", to: "system#test_pushover"
    post "validate_pushover_key", to: "system#validate_pushover_key"
    post "generate_web_push_keys", to: "system#generate_web_push_keys"

    # Restaurant settings
    get "restaurant/allowed_origins",  to: "restaurant#allowed_origins"
    post "restaurant/allowed_origins", to: "restaurant#update_allowed_origins"

    # Admin users => create/edit/delete + resend_invite + reset password
    resources :users, only: [ :index, :create, :update, :destroy ] do
      member do
        post :resend_invite
        post :admin_reset_password
      end
    end
  end

  # For ordering
  resources :orders, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      post :acknowledge
    end

    collection do
      get :unacknowledged
    end

    # Order payments routes
    resources :payments, only: [ :index ], controller: "order_payments" do
      collection do
        post :additional, to: "order_payments#create_additional"
        post "additional/capture", to: "order_payments#capture_additional"
        post :refund, to: "order_payments#create_refund"
        post :payment_link, to: "order_payments#create_payment_link"
        post :cash, to: "order_payments#process_cash_payment"
      end
    end

    # New routes for store credit and order total adjustment
    post "store-credit", to: "order_payments#add_store_credit"
    post "adjust-total", to: "order_payments#adjust_total"
  end

  resources :promo_codes, only: [ :index, :show, :create, :update, :destroy ]
  resources :menus, only: [ :index, :show, :create, :update, :destroy ]

  # Merchandise routes
  resources :merchandise_collections, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      post :set_active
    end
  end

  resources :merchandise_items, only: [ :index, :show, :create, :update, :destroy ] do
    member do
      post :upload_image
      patch :update_threshold
      post :upload_second_image
    end

    collection do
      get :low_stock
      get :out_of_stock
    end
  end

  resources :merchandise_variants, only: [ :index, :show, :create, :update, :destroy ] do
    collection do
      post :batch_create
    end

    member do
      post :add_stock
      post :reduce_stock
    end
  end

  # Enhanced menu_items with image uploading, option groups, and inventory tracking
  resources :menu_items do
    member do
      post :upload_image
      post :mark_as_damaged
      post :update_stock
      get :stock_audits
      post :copy
    end

    # For listing or creating option groups under a given menu item:
    resources :option_groups, only: [ :index, :create ]
  end

  # For updating or deleting an option group (requires just the group ID):
  resources :option_groups, only: [ :update, :destroy ] do
    # For creating options under a specific option group:
    resources :options, only: [ :create ]
  end

  # For updating or deleting a specific option (requires just the option ID)
  resources :options, only: [ :update, :destroy ]

  # Polling route for orders
  get "/orders/new_since/:id", to: "orders#new_since"

  # Payment routes
  get "/payments/client_token", to: "payments#client_token"
  post "/payments/process", to: "payments#process_payment"
  post "/payments/create_order", to: "payments#create_order"
  post "/payments/capture_order", to: "payments#capture_order"
  get "/payments/transaction/:id", to: "payments#transaction"

  # PayPal routes
  post "/paypal/create_order", to: "paypal#create_order"
  post "/paypal/capture_order", to: "paypal#capture_order"
  post "/paypal/webhook", to: "paypal#webhook"
  post "/paypal/webhook/:restaurant_id", to: "paypal#webhook"

  # Stripe routes
  post "/stripe/create_intent", to: "stripe#create_intent"
  post "/stripe/confirm_intent", to: "stripe#confirm_intent"
  get "/stripe/payment_intent/:id", to: "stripe#payment_intent"
  post "/stripe/webhook/:restaurant_id", to: "stripe#webhook"
  post "/stripe/webhook", to: "stripe#global_webhook"

  resources :inventory_statuses, only: [ :index, :show, :update ]

  # Profile
  get   "/profile", to: "users#show_profile"
  patch "/profile", to: "users#update_profile"
  
  # Web Push Notifications
  resources :push_subscriptions, only: [:index, :create, :destroy] do
    collection do
      post :unsubscribe
      get :vapid_public_key
    end
  end
  
  # Example routes for analytics demonstration (not for production use)
  namespace :examples do
    get 'analytics', to: 'analytics_example#index'
    get 'analytics/track_event', to: 'analytics_example#track_event'
    get 'analytics/identify_user', to: 'analytics_example#identify_user'
    get 'analytics/group_identify', to: 'analytics_example#group_identify'
  end
end

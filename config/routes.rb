Rails.application.routes.draw do
  # Authentication
  post '/signup', to: 'users#create'
  post '/login',  to: 'sessions#create'

  # Standard RESTful
  resources :restaurants, only: [:index, :show, :create, :update, :destroy]
  resources :seat_sections, only: [:index, :show, :create, :update, :destroy]

  resources :seats, only: [:index, :show, :create, :update, :destroy] do
    collection do
      post :bulk_update
    end
  end

  resources :reservations, only: [:index, :show, :create, :update, :destroy]
  resources :waitlist_entries, only: [:index, :show, :create, :update, :destroy]

  resources :seat_allocations, only: [:index, :create, :update, :destroy] do
    collection do
      post :multi_create
      post :reserve
      post :arrive
      post :no_show
      post :cancel
      post :finish
    end
  end

  resources :menus, only: [:index, :show, :create, :update, :destroy]
  resources :menu_items, only: [:index, :show, :create, :update, :destroy]
  resources :notifications, only: [:index, :show, :create, :update, :destroy]

  # Layouts
  resources :layouts, only: [:index, :show, :create, :update, :destroy] do
    member do
      post :activate
    end
  end

  # Availability route
  get '/availability', to: 'availability#index'
end

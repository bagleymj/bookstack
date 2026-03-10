Rails.application.routes.draw do
  devise_for :users

  # JWT API authentication
  scope "api/v1/auth", defaults: { format: :json } do
    post "sign_in", to: "api/v1/auth/sessions#create", as: :api_sign_in
    delete "sign_out", to: "api/v1/auth/sessions#destroy", as: :api_sign_out
    post "sign_up", to: "api/v1/auth/registrations#create", as: :api_sign_up
  end

  # Onboarding
  authenticate :user do
    resource :onboarding, only: [:show, :update], controller: "onboarding" do
      post :skip
    end
  end

  # Authenticated routes
  authenticate :user do
    root "dashboard#index", as: :authenticated_root

    get "dashboard", to: "dashboard#index"

    resources :books do
      member do
        post :start_reading
        post :mark_completed
        post :update_progress
      end
      resources :reading_sessions, only: [:new, :create], shallow: true do
        collection do
          post :start
        end
      end
    end

    resources :reading_sessions, only: [:index, :show, :edit, :update, :destroy] do
      member do
        post :complete
      end
    end

    resources :reading_goals, except: [:index] do
      member do
        post :mark_completed
        post :mark_abandoned
        get :redistribute
        post :redistribute
        post :catch_up
        post :resolve_discrepancy
      end
      resources :daily_quotas, only: [:update], shallow: true
    end

    resource :pipeline, only: [:show], controller: "pipeline"
    resource :profile, only: [:show, :update]
    get "reading_list", to: redirect("/pipeline")

    # Existing web API endpoints (session auth)
    namespace :api do
      namespace :v1 do
        resources :pipeline, only: [:index], controller: "pipeline"
        resources :active_books, only: [:index]
        resources :book_search, only: [:index] do
          collection do
            get :editions
          end
        end
        resources :reading_list, only: [:create, :destroy], controller: "reading_list" do
          collection do
            post :reorder
          end
        end
      end
    end
  end

  # Mobile API endpoints (JWT auth)
  namespace :api do
    namespace :v1 do
      resource :dashboard, only: [:show], controller: "dashboard"

      resources :books, controller: "books" do
        member do
          post :start_reading
          post :mark_completed
          post :update_progress
        end
      end

      resources :reading_sessions, controller: "reading_sessions" do
        collection do
          post :start
          get :active
        end
        member do
          post :stop
          post :complete
        end
      end

      resources :reading_goals, controller: "reading_goals" do
        member do
          post :mark_completed
          post :mark_abandoned
          post :redistribute
          post :catch_up
          post :resolve_discrepancy
        end
      end

      resources :daily_quotas, only: [:update], controller: "daily_quotas"

      resource :profile, only: [:show, :update], controller: "profiles"
      resource :stats, only: [:show], controller: "stats"
    end
  end

  # Unauthenticated root
  root "home#index"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end

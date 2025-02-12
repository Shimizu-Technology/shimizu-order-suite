# **Backend README**

# Hafaloha Backend (Rails API)

This is the **backend** of the Hafaloha application. It handles:
- **Reservations** management (storing and retrieving booking info).
- **Ordering** flow (creating orders, updating statuses).
- **Notifications**:
  - **SendGrid** for email
  - **ClickSend** for SMS
  - **Wassenger** for WhatsApp group notifications
- **AWS S3** for menu item images (upload or storage)
- **Sidekiq** + **Redis** for background job processing

The backend is built with **Ruby on Rails**, and is hosted on **Render**.

---

## **Architecture Overview**

- **Rails API** (API-only mode)  
- **PostgreSQL** for the primary database (also on Render).  
- **Redis** on Render for Sidekiq job queue.  
- **Sidekiq** as a background worker (hosted as a separate “Background Worker” service on Render).  
- **Enqueues** emails (`ActionMailer.deliver_later`) and texts (`SendSmsJob.perform_later`) asynchronously.  
- **Wassenger** is triggered from the `Order` model’s `after_create` callback, using `SendWhatsappJob` in the background.

---

## **Services & Hosting**

1. **Rails Web Service**: A Render service that runs `rails server`.  
2. **Redis Instance**: Also on Render, storing Sidekiq’s job queue.  
3. **Background Worker**: A separate Render service that runs `bundle exec sidekiq`.  
4. **PostgreSQL Database**: Another Render resource for the main DB.  
5. **AWS S3**: Hosting menu item images. The app references S3 URLs in the `menu_items.image_url`.  

---

## **Environment Variables**

Here are typical ENV variables used in this Rails app:

- **Database**:
  - `DATABASE_URL` – Provided by Render for connecting to PostgreSQL.  
- **Redis / Sidekiq**:
  - `REDIS_URL` – Provided by Render for connecting to Redis.  
- **ClickSend** (SMS):
  - `CLICKSEND_USERNAME`
  - `CLICKSEND_API_KEY`  
- **SendGrid** (Emails):
  - `SENDGRID_USERNAME` (or sometimes just API key)  
  - `SENDGRID_API_KEY`  
- **Wassenger** (WhatsApp):
  - `WASSENGER_API_KEY` – if needed by your custom `WassengerClient` class
  - `WASSENGER_GROUP_ID` – the group to message  
- **AWS S3**:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
  - `S3_BUCKET_NAME`
- **Rails**:
  - `RAILS_ENV=production`
  - `SECRET_KEY_BASE` (should be set automatically by Render if you have auto config)

Depending on how you’ve structured your code, you might have more or fewer environment variables. Make sure both your **web** and **worker** services (on Render) have these variables set so they can operate in the same environment.

---

Below is an **updated** backend `README.md` section with properly formatted steps for **local development** and **production deployment**, including how to install and start **Redis** and **PostgreSQL** on macOS (via Homebrew). Adjust these instructions for your OS or hosting preference as needed.

---

## **Local Development Setup**

1. **Clone the Repository**  
   ```bash
   git clone https://github.com/YourUsername/hafaloha-backend.git
   cd hafaloha-backend
   ```

2. **Install Ruby Gems**  
   ```bash
   bundle install
   ```

3. **Install and Start PostgreSQL** (macOS example using Homebrew)  
   ```bash
   brew install postgresql
   brew services start postgresql
   ```
   Alternatively, use your preferred PostgreSQL setup if you already have it installed or are on a different OS.

4. **Create and Migrate the Database**  
   ```bash
   rails db:create
   rails db:migrate
   ```
   *Optional:* If you have seed data, run:  
   ```bash
   rails db:seed
   ```

5. **Install and Start Redis** (for Sidekiq)  
   ```bash
   brew install redis
   brew services start redis
   ```
   (On other OSes, install Redis via your package manager or Docker.)

6. **Run Sidekiq** in a Separate Terminal  
   ```bash
   bundle exec sidekiq -C config/sidekiq.yml
   ```
   This will continuously process background jobs.

7. **Start Rails Server**  
   ```bash
   rails server
   ```
   By default, Rails listens on `http://localhost:3000`.

Now you can test the API at `http://localhost:3000`. If you have a frontend pointing to this API, set its environment variable (e.g., `VITE_API_BASE_URL`) to `http://localhost:3000`.

---

## **Production Deployment to Render**

1. **Create a Web Service** on Render for your Rails app.  
   - **Build Command**:  
     ```bash
     bundle install && bundle exec rails db:migrate
     ```
   - **Start Command**:  
     ```bash
     bundle exec rails server -p 3001
     ```
     (or whichever port you prefer)
   - **Environment Variables**:  
     - `DATABASE_URL` (Pointing to your Render PostgreSQL)
     - `REDIS_URL`   (Pointing to your Render Redis instance)
     - `SECRET_KEY_BASE`, `RAILS_ENV=production`, etc.
     - Any API keys (`CLICKSEND_*`, `SENDGRID_*`, etc.)

2. **Create a Background Worker** (Sidekiq) on Render.  
   - **Build Command**:  
     ```bash
     bundle install && bundle exec rails db:migrate
     ```
   - **Start Command**:  
     ```bash
     bundle exec sidekiq -C config/sidekiq.yml
     ```
   - **Environment Variables**:  
     - Same as above (`REDIS_URL`, etc.) so it can connect to the same database & Redis.

3. **Create (or Link) Your Redis Instance**  
   - Render provides a `REDIS_URL`. Copy it into both your Web Service and Worker’s environment.

4. **Deploy**  
   - Upon each push, Render rebuilds and deploys your **web** and **worker** services.  
   - The **worker** continuously processes background jobs (emails, SMS, WhatsApp), while the **web** service handles HTTP requests.

---

## **Running Tests**

If you have a test suite (e.g., **RSpec**):

```bash
bundle exec rspec
```

Or with **Minitest**:

```bash
bundle exec rails test
```

---

## **Contact & Support**

If you have questions about:

- **Architecture** (reservations vs. ordering)
- **Messaging logic** (SMS/WhatsApp/Email)
- **Sidekiq background jobs**

Please check the inline code comments or contact the dev team. 

**Thank you for using Hafaloha!**
require "sinatra/base"
require "json"
require "logger"
require "sequel"
require "pg"

# Load only what we need — database models and jobs.
# We deliberately do NOT load config/application.rb because it pulls in
# AWS SDKs, encrypted credentials, Sentry, CallPlatform, and SomlengRegion
# initializers that are not needed (or available) for on-prem HTTP mode.

require_relative "app/models/database_connection"
require_relative "app/models/database_connections"
require_relative "app/models/application_record"
require_relative "app/models/opensips_subscriber"
require_relative "app/models/opensips_address"
require_relative "app/models/opensips_domain"

require_relative "app/jobs/create_opensips_subscriber_job"
require_relative "app/jobs/delete_opensips_subscriber_job"
require_relative "app/jobs/create_opensips_permission_job"
require_relative "app/jobs/update_opensips_permission_job"
require_relative "app/jobs/delete_opensips_permission_job"

class ServicesServer < Sinatra::Base
  set :port, ENV.fetch("PORT", 3000)
  set :bind, "0.0.0.0"
  set :logging, true

  ALLOWED_JOB_CLASSES = %w[
    CreateOpenSIPSSubscriberJob
    DeleteOpenSIPSSubscriberJob
    CreateOpenSIPSPermissionJob
    UpdateOpenSIPSPermissionJob
    DeleteOpenSIPSPermissionJob
  ].freeze

  helpers do
    def authenticate!
      return if authorized?
      headers["WWW-Authenticate"] = 'Basic realm="Services"'
      halt 401, { error: "Unauthorized" }.to_json
    end

    def authorized?
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && @auth.credentials &&
        @auth.credentials[0] == ENV.fetch("SERVICES_AUTH_USERNAME", "services") &&
        @auth.credentials[1] == ENV.fetch("SERVICES_AUTH_PASSWORD")
    end
  end

  before do
    content_type :json
  end

  get "/health" do
    { status: "ok" }.to_json
  end

  post "/jobs" do
    authenticate!

    payload = JSON.parse(request.body.read)
    job_class_name = payload["job_class"]
    job_args = payload["job_args"]

    unless ALLOWED_JOB_CLASSES.include?(job_class_name)
      logger.error("Rejected job class: #{job_class_name}")
      halt 422, { error: "Unknown job class: #{job_class_name}" }.to_json
    end

    logger.info("Processing job: #{job_class_name}")

    job_class = Object.const_get(job_class_name)
    job_class.new(*job_args).call

    status 202
    { status: "ok", job_class: job_class_name }.to_json
  rescue => e
    logger.error("Job failed: #{e.class} - #{e.message}")
    status 500
    { error: e.message }.to_json
  end

  run! if __FILE__ == $PROGRAM_NAME
end

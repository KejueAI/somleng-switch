class ExecuteDial < ExecuteTwiMLVerb
  DIAL_CALL_STATUSES = {
    no_answer: "no-answer",
    answer: "completed",
    timeout: "no-answer",
    error: "failed",
    busy: "busy",
    in_progress: "in-progress",
    ringing: "ringing"
  }.freeze

  attr_reader :call_update_event_handler

  def initialize(verb, **options)
    super
    @call_update_event_handler = options.fetch(:call_update_event_handler) { CallUpdateEventHandler.new }
  end

  def call
    conference_noun = verb.nested_nouns.find { |n| n.is_a?(TwiML::DialVerb::ConferenceNoun) }

    if conference_noun
      execute_conference(conference_noun)
    else
      execute_outbound_dial
    end
  end

  private

  # ---- Standard outbound dial (unchanged from upstream) ----

  def execute_outbound_dial
    answer!
    phone_calls = create_outbound_calls
    dial_params = build_dial_params(phone_calls)
    dial_status = context.dial(dial_params)

    return if verb.action.blank?

    callback_params = build_callback_params(dial_status)
    redirect(callback_params)
  end

  def create_outbound_calls
    call_platform_client.create_outbound_calls(
      destinations: verb.nested_nouns.map { |nested_noun| nested_noun.content.strip },
      parent_call_sid: call_properties.call_sid,
      from: verb.caller_id
    )
  end

  def build_dial_params(phone_calls)
    phone_calls.each_with_object({}) do |phone_call, result|
      dial_string, from = build_dial_string(phone_call)

      result[dial_string.to_s] = {
        from:,
        for: verb.timeout.seconds,
        headers: SIPHeaders.new(
          call_sid: phone_call.sid,
          account_sid: phone_call.account_sid
        ).to_h
      }.compact
    end
  end

  def build_dial_string(phone_call_response)
    if phone_call_response.address.present?
      DialString.new(address: phone_call_response.address)
    else
      dial_string = DialString.new(phone_call_response.routing_parameters)
      [ dial_string, dial_string.format_number(phone_call_response.from) ]
    end
  end

  def redirect(params)
    throw(
      :redirect,
      {
        url: verb.action,
        http_method: verb.method,
        params:
      }
    )
  end

  def build_callback_params(dial_status)
    result = {}
    result["DialCallStatus"] = DIAL_CALL_STATUSES.fetch(dial_status.result)

    if (joined_call = find_joined_call(dial_status))
      result["DialCallSid"] = joined_call.id
      result["DialCallDuration"] = dial_status.joins[joined_call].duration.to_i
    end

    result
  end

  def find_joined_call(dial_status)
    dial_status.joins.find do |outbound_call, join_status|
      return outbound_call if join_status.result == :joined
    end
  end

  # ---- Conference join ----

  def execute_conference(conference_noun)
    answer!

    room_name = conference_noun.room_name
    logger.info "Joining conference: #{room_name} (startOnEnter=#{conference_noun.start_conference_on_enter}, endOnExit=#{conference_noun.end_conference_on_exit}, muted=#{conference_noun.muted})"

    # Subscribe to call update events so the platform can redirect this call
    # out of the conference (e.g., for warm transfer bridging or cancellation).
    # This mirrors how ExecuteConnect handles call updates during <Connect><Stream>.
    subscribe_channel = call_update_event_handler.channel_for(phone_call.id)

    # Track whether we left via call update (redirect) vs normal unjoin
    redirected = false

    redis = AppSettings.redis
    redis.with do |connection|
      # Start a background thread to listen for call update events
      listener_thread = Thread.new do
        begin
          connection.subscribe(subscribe_channel) do |on|
            on.message do |_channel, message|
              event = call_update_event_handler.parse_event(message)
              call_update_event_handler.perform_later(event)
              redirected = true

              # Unjoin the call from the conference to unblock the main thread
              begin
                context.call.unjoin(mixer_name: room_name)
              rescue => e
                logger.warn "Failed to unjoin from conference #{room_name}: #{e.message}"
              end

              connection.unsubscribe
            end
          end
        rescue => e
          logger.warn "Conference call update listener error: #{e.message}"
        end
      end

      # Join the conference (blocks until unjoined)
      begin
        join_options = { mixer_name: room_name }
        context.join(join_options)
      rescue Adhearsion::Call::Hangup, Adhearsion::DisconnectedError => e
        logger.info "Call disconnected from conference #{room_name}: #{e.class}"
      rescue => e
        logger.error "Error joining conference #{room_name}: #{e.message}"
      ensure
        # Make sure the listener thread is cleaned up
        begin
          listener_thread.kill if listener_thread.alive?
        rescue => e
          logger.warn "Error cleaning up listener thread: #{e.message}"
        end
      end
    end

    # Process any queued call update events (redirect to new TwiML)
    if redirected
      call_update_event_handler.perform_queued
    elsif verb.action.present?
      # Normal conference exit (everyone left or hangup) — redirect to action URL
      redirect({})
    end
  end

  def logger
    @logger ||= Adhearsion::Logging.get_logger(self.class)
  end
end

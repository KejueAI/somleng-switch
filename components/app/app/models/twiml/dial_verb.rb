require_relative "twiml_node"

module TwiML
  class DialVerb < TwiMLNode
    class Parser < TwiML::NodeParser
      VALID_NOUNS = %w[Number Sip Conference].freeze

      def parse(node)
        super.merge(
          nested_nouns: parse_nested_nouns
        )
      end

      private

      def parse_nested_nouns
        nested_nodes.map do |nested_node|
          if nested_node.name == "Conference"
            ConferenceNoun.parse(nested_node)
          else
            TwiMLNode.parse(nested_node)
          end
        end
      end

      def valid?
        validate_nested_nouns
        super
      end

      def validate_nested_nouns
        return if nested_nodes.all? { |nested_node| VALID_NOUNS.include?(nested_node.name) || nested_node.text? }

        invalid_node = nested_nodes.find { |v| VALID_NOUNS.exclude?(v.name) }
        errors.add("<#{invalid_node.name}> is not allowed within <Dial>")
      end
    end

    # Conference noun: <Conference startConferenceOnEnter="true" endConferenceOnExit="false"
    #   muted="false" beep="true" waitUrl="" waitMethod="POST">room-name</Conference>
    class ConferenceNoun < TwiMLNode
      class Parser < TwiML::NodeParser
        def parse(node)
          node_options = super
          node_options[:room_name] = node.content.strip
          node_options[:start_conference_on_enter] = parse_bool(attributes["startConferenceOnEnter"], true)
          node_options[:end_conference_on_exit] = parse_bool(attributes["endConferenceOnExit"], false)
          node_options[:muted] = parse_bool(attributes["muted"], false)
          node_options[:beep] = parse_bool(attributes["beep"], true)
          node_options[:wait_url] = attributes["waitUrl"]
          node_options[:wait_method] = attributes.fetch("waitMethod", "POST")
          node_options[:max_participants] = attributes.fetch("maxParticipants", "10").to_i
          node_options[:status_callback] = attributes["statusCallback"]
          node_options[:status_callback_event] = attributes["statusCallbackEvent"]
          node_options
        end

        private

        def parse_bool(value, default)
          return default if value.nil?
          value.to_s.downcase == "true"
        end

        def valid?
          validate_room_name
          super
        end

        def validate_room_name
          room_name = node.content.strip
          return if room_name.present?

          errors.add("<Conference> must contain a room name")
        end
      end

      class << self
        def parse(node)
          super(node, parser: Parser.new)
        end
      end

      attr_reader :room_name, :start_conference_on_enter, :end_conference_on_exit,
                  :muted, :beep, :wait_url, :wait_method, :max_participants,
                  :status_callback, :status_callback_event

      def initialize(room_name:, start_conference_on_enter:, end_conference_on_exit:,
                     muted:, beep:, wait_url:, wait_method:, max_participants:,
                     status_callback:, status_callback_event:, **options)
        super(**options)
        @room_name = room_name
        @start_conference_on_enter = start_conference_on_enter
        @end_conference_on_exit = end_conference_on_exit
        @muted = muted
        @beep = beep
        @wait_url = wait_url
        @wait_method = wait_method
        @max_participants = max_participants
        @status_callback = status_callback
        @status_callback_event = status_callback_event
      end
    end

    class << self
      def parse(node)
        super(node, parser: Parser.new)
      end
    end

    attr_reader :nested_nouns

    def initialize(nested_nouns:, **options)
      super(**options)
      @nested_nouns = nested_nouns
    end

    def action
      attributes["action"]
    end

    def method
      attributes["method"]
    end

    def caller_id
      attributes["callerId"]
    end

    def timeout
      attributes.fetch("timeout", 30).to_i
    end
  end
end

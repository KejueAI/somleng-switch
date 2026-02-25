class DialString
  attr_reader :options

  DEFAULT_SIP_PROFILE = "nat_gateway".freeze

  def initialize(options)
    @options = options.symbolize_keys
  end

  def to_s
    if outbound_registration?
      # Route through the gateway so FreeSWITCH handles 401 digest auth automatically.
      # Override the Request-URI to use the hostname (not resolved IP) and correct port.
      host = outbound_host_name
      "{sip_invite_req_uri=sip:#{formatted_destination}@#{host},sip_invite_domain=#{host}}sofia/gateway/#{gateway_name}/#{formatted_destination}"
    else
      "{sofia_suppress_url_encoding=true,sip_invite_domain=#{destination_host}}sofia/#{external_profile}/#{address}"
    end
  end

  def address
    options.fetch(:address) { routing_parameters.address }
  end

  def format_number(...)
    routing_parameters.format_number(...)
  end

  private

  def outbound_registration?
    options[:authentication_mode] == "outbound_registration"
  end

  def gateway_name
    options.fetch(:gateway_name)
  end

  def outbound_host
    options.fetch(:host)
  end

  def outbound_host_name
    outbound_host.split(":").first
  end

  def formatted_destination
    routing_parameters.format_number(options.fetch(:destination)).gsub(/\D/, "")
  end

  def destination_host
    address.split("@").last.split(":").first
  end

  def routing_parameters
    @routing_parameters ||= RoutingParameters.new(options)
  end

  def external_profile
    options.fetch(:sip_profile, DEFAULT_SIP_PROFILE)
  end
end

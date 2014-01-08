ENV["BUNDLE_GEMFILE"] = File.expand_path("./Gemfile", File.dirname(__FILE__))
RACK_ENV ||= ENV["RACK_ENV"] || "development"

require "bundler/setup"
require "sinatra"
require "statsd"

# Default app settings
set :environment, RACK_ENV.to_sym
set :logging, true
set :raise_errors, true

class StatsdMinimal
  def rand
    0.0
  end
end

def build_client
  client = Statsd.new ENV['STATSD_HOST'], ENV['STATSD_PORT']

  # Sample rate behaviour is already implemented in the
  # client.  We want to pass it to the statsd server,
  # but we don't want Statsd to act on it.
  def client.rand
    0.0
  end

  client
end

def statsd
  if settings.test?
    build_client
  else
    $statsd ||= build_client
  end
end

def parse_number(str)
  str.include?('.') ? str.to_f : str.to_i
end

STATSD_METHODS = {
  'c'  => :count,
  'g'  => :gauge,
  'h'  => :histogram,
  'ms' => :timing,
  's'  => :set
}

post '/' do
  type   = params['t'].to_s
  method = STATSD_METHODS[type]
  return 415 unless method

  stat  = "minecraft.#{params['s']}"
  value = parse_number(params['v'])
  rate  = params['r'].to_f

  tags = params.select { |k, v| k.start_with?('_') }.map do |k, v|
    k = k.gsub(/:+/, '_')
    "#{k}:#{v}"
  end

  opts = {}
  opts[:sample_rate] = rate if rate > 0.0
  opts[:tags] = tags unless tags.empty?

  statsd.send(method, stat, value, opts)
  200
end

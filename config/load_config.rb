require 'ostruct'

config_file = "/etc/mongoid.yml"
if !File.exist?(config_file)
  config_file = Rails.root+"config/mongoid.yml"
end

if !File.exist?(config_file)
  raise StandardError,  "Config file was not found"
end

options = YAML.load_file(config_file)
if !options[Rails.env]
  raise "'#{Rails.env}' was not found in #{config_file}"
end

AppConfig = OpenStruct.new(options[Rails.env])

# check config
unless ENV["mongoid_NO_CHECK_CONFIG"]
  begin
    known_options = YAML.load_file(Rails.root+"config/mongoid.yml.sample")[Rails.env]
    if known_options
      known_options.each do |k, v|
        if AppConfig.send(k).nil?
          $stderr.puts "Warning: missing config option: '#{k}'"
        end
      end
    end
  end
end

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require 'minitest/autorun'
require 'active_support/all'
require 'active_record'
require 'datasource'

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

# ActiveRecord::Base.logger = Logger.new STDOUT

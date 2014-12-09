# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require 'minitest/autorun'
require 'active_support/all'
require 'active_record'
require 'datasource'
require 'active_model_serializers'
require 'pry'

Datasource.load(:activerecord)

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

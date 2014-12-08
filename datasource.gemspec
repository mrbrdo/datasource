Gem::Specification.new do |s|
  s.name               = "datasource"
  s.version            = "0.0.1"

  s.authors = ["Jan Berdajs"]
  s.date = %q{2014-11-08}
  s.email       = ["mrbrdo@gmail.com"]
  s.homepage    = "https://github.com/mrbrdo/datasource"
  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.md"]
  s.test_files = Dir["test/**/*"]
  s.require_paths = ["lib"]
  s.summary = %q{Ruby library for creating data source objects from database data}
  s.licenses    = ['MIT']

  s.add_dependency 'activerecord', '~> 4'
  s.add_dependency 'active_model_serializers', '>= 0.9'
  s.add_development_dependency 'pry', '~> 0.9'
  s.add_development_dependency 'activesupport', '~> 4'
end


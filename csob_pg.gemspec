# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'csob_pg'
  s.version     = '0.0.4'
  s.date        = '2025-04-08'
  s.summary     = 'Implementation of a client to communicate with the payment gateway operated by ČSOB (Czechoslovak Trade Bank), API v1.9'
  s.authors     = ['iQuest s.r.o.']
  s.email       = 'info@iquest.cz'
  s.files       = ['lib/csob_pg/constants.rb',
                   'lib/csob_pg/message.rb',
                   'lib/csob_pg/client.rb',
                   'lib/csob_pg/configuration.rb',
                   'lib/csob_pg.rb']
  s.required_ruby_version = '>= 3.1.0'
  s.add_dependency 'dry-struct', '~> 1'
  s.add_dependency 'rest-client', '~> 2'
  s.add_development_dependency 'dotenv', '~> 2'
  s.add_development_dependency 'nokogiri', '~> 1'
end

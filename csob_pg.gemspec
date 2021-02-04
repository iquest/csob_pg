Gem::Specification.new do |s|
  s.name        = 'csob_pg'
  s.version     = '0.0.2'
  s.date        = '2021-02-04'
  s.summary     = 'Implementation of a client to communicate with the payment gateway operated by ČSOB (Czechoslovak Trade Bank), API v1.8'
  s.authors     = ['Tomáš Milsimer']
  s.email       = 'tomas.milsimer@protonmail.com'
  s.files       = ['lib/csob_pg/constants.rb',
                   'lib/csob_pg/message.rb',
                   'lib/csob_pg/client.rb',
                   'lib/csob_pg/configuration.rb',
                   'lib/csob_pg.rb']
   s.add_dependency 'rest-client', '~> 2'
   s.add_dependency 'dry-struct', '~> 1'
   s.add_development_dependency 'nokogiri', '~> 1'
end

# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'csob_pg'
  s.version     = '0.0.7'
  s.summary     = 'Implementation of a client for payment gateway operated by ČSOB (Czechoslovak Trade Bank)'
  s.description =  <<~DESCRIPTION
    Implementation of a client to communicate with the payment gateway operated
    by ČSOB (Czechoslovak Trade Bank).
  DESCRIPTION
  s.authors     = ['iQuest s.r.o.']
  s.email       = 'info@iquest.cz'
  s.licenses    = ['MIT']
  s.homepage    = 'https://github.com/iquest/csob_pg'
  s.files       = ['lib/csob_pg/constants.rb',
                   'lib/csob_pg/message.rb',
                   'lib/csob_pg/client.rb',
                   'lib/csob_pg/configuration.rb',
                   'lib/csob_pg/http_client.rb',
                   'lib/csob_pg.rb']
  s.required_ruby_version = '>= 3.1.0'
  s.add_dependency 'base64', '~> 0.3'
  s.add_dependency 'dry-struct', '~> 1'
  s.add_dependency 'net-http', '~> 0.6'
  s.add_dependency 'uri', '~> 1'
  s.metadata['rubygems_mfa_required'] = 'true'
end

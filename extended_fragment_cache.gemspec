# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{extended_fragment_cache}
  s.version = "0.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["tylerkovacs"]
  s.date = %q{2009-02-11}
  s.description = %q{See README}
  s.email = %q{tyler.kovacs@gmail.com}
  s.files = ["VERSION.yml", "lib/extended_fragment_cache.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/tylerkovacs/extended_fragment_cache}
  s.rdoc_options = ["--inline-source", "--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{The extended_fragment_cache plugin provides content interpolation and an in-process memory cache for fragment caching.}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end

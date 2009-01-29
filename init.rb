require 'extended_fragment_cache'

ActionController::Base.send :include, ActionController::Caching::ExtendedFragments

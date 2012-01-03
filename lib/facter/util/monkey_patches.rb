# This provides an alias for RbConfig to Config for pre-ruby 1.8.5 revisions.
require 'rbconfig'
unless defined? ::RbConfig
  ::RbConfig = ::Config
end

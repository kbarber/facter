#!/usr/bin/env rspec

$basedir = File.expand_path(File.dirname(__FILE__) + '/../..')
require File.join($basedir, 'spec_helper')

require 'facter/util/cache/persistent_hash'

describe Facter::Util::Cache::PersistentHash do
end

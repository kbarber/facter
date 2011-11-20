#!/usr/bin/env ruby

require 'spec_helper'
require 'facter/util/cache'

describe Facter::Util::Config do
  describe "is_windows? function" do
    it "should detect windows if RbConfig returns a windows OS" do
      host_os = ["mswin","win32","dos","mingw","cygwin"]
      host_os.each do |h|
        Config::CONFIG.stubs(:[]).with('host_os').returns(h)
        Facter::Util::Config.is_windows?.should be_true
      end
    end

    it "should not detect windows if RbConfig returns a non-windows OS" do
      host_os = ["darwin","linux"]
      host_os.each do |h|
        Config::CONFIG.stubs(:[]).with('host_os').returns(h)
        Facter::Util::Config.is_windows?.should be_false
      end
    end
  end

  describe "is_mac? function" do
    it "should detect mac if RbConfig returns darwin" do
      host_os = ["darwin"]
      host_os.each do |h|
        Config::CONFIG.stubs(:[]).with('host_os').returns(h)
        Facter::Util::Config.is_mac?.should be_true
      end
    end
  end
end

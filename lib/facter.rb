# Facter - Host Fact Detection and Reporting
#
# Copyright 2011 Puppet Labs Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Facter
  # This is just so the other classes have the constant.
  module Util; end

  require 'facter/util/fact'
  require 'facter/util/collection'

  include Comparable
  include Enumerable

  FACTERVERSION = '1.6.4'
  # = Facter
  # Functions as a hash of 'facts' you might care about about your
  # system, such as mac address, IP address, Video card, etc.
  # returns them dynamically

  # == Synopsis
  #
  # Generally, treat <tt>Facter</tt> as a hash:
  # == Example
  # require 'facter'
  # puts Facter['operatingsystem']
  #

  # Set LANG to force i18n to C
  #
  ENV['LANG'] = 'C'

  GREEN = "[0;32m"
  RESET = "[0m"
  @@debug = 0
  @@timing = 0
  @@messages = {}
  @@cache_enabled = 0
  @@ignorettl = 0

  # module methods

  def self.collection
    unless defined?(@collection) and @collection
      @collection = Facter::Util::Collection.new
    end
    @collection
  end

  def self.cache
    unless defined?(@cache) and @cache
      @cache = Facter::Util::Cache.new
    end
    @cache
  end

  # Return the version of the library.
  def self.version
    return FACTERVERSION
  end

  # Add some debugging
  def self.debug(string)
    if string.nil?
      return
    end
    if self.debugging?
      puts GREEN + string + RESET
    end
  end

  def self.debugging?
    @@debug != 0
  end

  # show the timing information
  def self.show_time(string)
    puts "#{GREEN}#{string}#{RESET}" if string and Facter.timing?
  end

  def self.timing?
    @@timing != 0
  end

  def self.cache_enabled?
    @@cache_enabled != 0
  end

  def self.ignorettl?
    @@ignorettl != 0
  end

  # Return a fact object by name.  If you use this, you still have to call
  # 'value' on it to retrieve the actual value.
  def self.[](name)
    collection.fact(name)
  end

  class << self
    [:fact, :flush, :list, :value].each do |method|
      define_method(method) do |*args|
        collection.send(method, *args)
      end
    end

    [:list, :to_hash].each do |method|
      define_method(method) do |*args|
        collection.load_all
        collection.send(method, *args)
      end
    end
  end


  # Add a resolution mechanism for a named fact.  This does not distinguish
  # between adding a new fact and adding a new way to resolve a fact.
  def self.add(name, options = {}, &block)
    collection.add(name, options, &block)
  end

  def self.each
    # Make sure all facts are loaded.
    collection.load_all

    collection.each do |*args|
      yield(*args)
    end
  end

  class << self
    # Allow users to call fact names directly on the Facter class,
    # either retrieving the value or comparing it to an existing value.
    def method_missing(name, *args)
      question = false
      if name.to_s =~ /\?$/
        question = true
        name = name.to_s.sub(/\?$/,'')
      end

      if fact = collection.fact(name)
        if question
          value = fact.value.downcase
          args.each do |arg|
            if arg.to_s.downcase == value
              return true
            end
          end

          # If we got this far, there was no match.
          return false
        else
          return fact.value
        end
      else
        # Else, fail like a normal missing method.
        raise NoMethodError, "Could not find fact '%s'" % name
      end
    end
  end

  # Clear all facts.  Mostly used for testing.
  def self.clear
    Facter.flush
    Facter.reset
  end

  # Clear all messages. Used only in testing. Can't add to self.clear
  # because we don't want to warn multiple times for items that are warnonce'd
  def self.clear_messages
    @@messages.clear
  end

  # Set debugging on or off.
  def self.debugging(bit)
    if bit
      case bit
      when TrueClass; @@debug = 1
      when FalseClass; @@debug = 0
      when Fixnum
        if bit > 0
          @@debug = 1
        else
          @@debug = 0
        end
      when String;
        if bit.downcase == 'off'
          @@debug = 0
        else
          @@debug = 1
        end
      else
        @@debug = 0
      end
    else
      @@debug = 0
    end
  end

  # Set timing on or off.
  def self.timing(bit)
    if bit
      case bit
      when TrueClass; @@timing = 1
      when Fixnum
        if bit > 0
          @@timing = 1
        else
          @@timing = 0
        end
      end
    else
      @@timing = 0
    end
  end

  # Set cache on or off.
  def self.cache_enabled(bit)
    @@cache_enabled = bitcheck(bit)
  end

  def self.ignorettl(bit)
    @@ignorettl = bitcheck(bit)
  end

  def self.bitcheck(bit)
    if bit
      case bit
      when TrueClass; return 1
      when FalseClass; return 0
      when Fixnum
        if bit > 0
          return 1
        else
          return 0
        end
      end
    else
      return 0
    end
  end

  def self.warn(msg)
    if Facter.debugging? and msg and not msg.empty?
      msg = [msg] unless msg.respond_to? :each
      msg.each { |line| Kernel.warn line }
    end
  end

  # Warn once.
  def self.warnonce(msg)
    if msg and not msg.empty? and @@messages[msg].nil?
      @@messages[msg] = true
      Kernel.warn(msg)
    end
  end

  # Remove them all.
  def self.reset
    @collection = nil
  end

  # Load all of the default facts, and then everything from disk.
  def self.loadfacts
    collection.load_all
  end

  @search_path = []

  # Register a directory to search through.
  def self.search(*dirs)
    @search_path += dirs
  end

  # Return our registered search directories.
  def self.search_path
    @search_path.dup
  end

  # The basedir to use for windows data
  def self.windows_data_dir
    # If neither environment variable is set - fail.
    if not ENV["ProgramData"] and not ENV["ALLUSERSPROFILE"] then
      raise "Neither environment variables ProgramData or ALLUSERSPROFILE " +
        "are defined. Facter is unable to determine a default dirctory for " +
        "its uses."
    end
    base_dir = ENV["ProgramData"] ||
      File.join(ENV["ALLUSERSPROFILE"], "Application Data")
    File.join(base_dir, "Puppetlabs", "facter")
  end

  # Retrieve the cache file path
  def self.cachedir
    if Facter::Util::Config.is_windows?
      @@cachedir ||= File.join(windows_data_dir, "cache/")
    elsif Facter::Util::Config.is_mac?
      @@cachedir ||= "/var/db/facter/cache/"
    else
      @@cachedir ||= "/var/cache/facter/"
    end
    @@cachedir
  end

  # Set the current cache file path
  def self.cachedir=(path)
    @@cachedir = path

    # Clear the cache variable since resetting the cachedir will require
    # require re-initialization
    @cache = nil
  end

end

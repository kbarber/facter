# A module to return config related data
#
module Facter::Util::Config
  require 'rbconfig'

  # Returns true if OS is windows
  def self.is_windows?
    Config::CONFIG['host_os'] =~ /mswin|win32|dos|mingw|cygwin/i
  end

  # Returns true if OS is Mac
  def self.is_mac?
    Config::CONFIG['host_os'] =~ /darwin/i
  end
end

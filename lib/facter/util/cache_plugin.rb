# Plugin class
class Facter::Util::CachePlugin
  def self.inherited(klass)
    @subclasses ||= []
    @subclasses << klass
  end
end

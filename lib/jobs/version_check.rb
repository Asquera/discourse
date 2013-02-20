require_dependency 'discourse_hub'
require_dependency 'discourse_updates'

module Jobs
  class VersionCheck < Jobs::Base

    def execute(args)
      json = DiscourseHub.discourse_version_check
      DiscourseUpdates.latest_version = json['latestVersion']
      DiscourseUpdates.critical_update_available = json['criticalUpdates']
      true
    end

  end
end
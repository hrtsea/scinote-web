# frozen_string_literal: true

# InstanceAdmin is defined and registered in app/permissions/instance_admin.rb
# (loaded by the canaid railtie during boot). This file only re-opens the module
# so Zeitwerk's autoload bookkeeping stays consistent across the two autoload
# roots that both contain an instance_admin.rb.
module InstanceAdmin
end

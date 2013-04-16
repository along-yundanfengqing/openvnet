# -*- coding: utf-8 -*-

module Vnmgr

  VNMGR_ROOT = ENV['VNMGR_ROOT'] || File.expand_path('../../', __FILE__)

  module NodeModules
    autoload :ServiceOpenflow, 'vnmgr/node_modules/service_openflow'
  end

end

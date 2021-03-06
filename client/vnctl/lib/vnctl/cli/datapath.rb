# -*- coding: utf-8 -*-

module Vnctl::Cli
  class Datapath < Base
    namespace :datapaths
    api_suffix 'datapaths'

    add_modify_shared_options {
      option_display_name
      option :dpid, :type => :string, :desc => 'Hexadecimal id for the datapath.'
      option :node_id, :type => :string, :desc => 'The node id for the datapath.'
      option :enable_ovs_learn_action, :type => :boolean, :desc => 'Enables the datapath to use OVS learning flows.'
    }
    set_required_options [:dpid, :node_id]

    define_standard_crud_commands

    define_relation :networks do |relation|
      relation.option :mac_address, :type => :string, :required => false,
        :desc => 'The broadcast mac address for mac2mac to use in this network.'
      relation.option :interface_uuid, :type => :string, :required => true,
        :desc => 'The host interface uuid to use for this network.'
    end

    define_relation :segments do |relation|
      relation.option :mac_address, :type => :string, :required => false,
        :desc => 'The broadcast mac address for mac2mac to use in this segment.'
      relation.option :interface_uuid, :type => :string, :required => true,
        :desc => 'The host interface uuid to use for this segment.'
    end

    define_relation :route_links do |relation|
      relation.option :mac_address, :type => :string, :required => false,
        :desc => 'The mac address to use for this link'
      relation.option :interface_uuid, :type => :string, :required => true,
        :desc => 'The host interface uuid to use for this route link.'
    end
  end
end

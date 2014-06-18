# -*- coding: utf-8 -*-

require 'ipaddr'
require 'trema'
require 'active_support/inflector'

module Vnet::Plugins
  class VdcVnetPlugin
    include Celluloid
    include Celluloid::Logger

    attr_reader :table
    attr_reader :gw_prefix, :datapath_route_link_prefix, :route_link_prefix

    def initialize
      @table = {
        # :vdc_model => :vnet_model
        :Network => [:Network],
        :NetworkVif => [:Interface],
        :NetworkVifIpLease => [:IpLease],
        :NetworkService => [:NetworkService],
        :NetworkRoute => [:TranslationStaticAddress]
      }

      @gw_prefix = "00:99:99"
      @datapath_route_link_prefix = "00:99:98"
      @route_link_prefix = "00:99:97"

      info "vdc_vnet_plugin initialized..."
    end

    def create_entry(vdc_model_class, vnet_params)
      table[vdc_model_class].each do |vnet_model_class|
        ret = send("#{vnet_model_class.to_s.underscore}_params", vnet_params)
        Vnet::NodeApi.const_get(vnet_model_class).create(vnet_params) unless ret == -1
      end
    end

    def destroy_entry(vdc_model_class, uuid)
      vnet_model_class = table[vdc_model_class]
      Vnet::NodeApi.const_get(vnet_model_class).destroy(uuid)
    end

    private

    def network_service_params(vnet_params)
      si_params = simulated_interface_params(vnet_params)

      return -1 unless ['dns', 'dhcp'].include? vnet_params[:name]

      if si_params[:network_id].nil?
        info "#{vnet_params[:network_uuid]} does not exist on vnet"
        return
      end

      interface = Vnet::NodeApi.const_get(:Interface).create(si_params)

      vnet_params[:interface_id] = interface.id
      vnet_params[:type] = vnet_params.delete(:name)

      vnet_params.delete(:ipv4_address)
      vnet_params.delete(:mac_address)
      vnet_params.delete(:network_id)
      vnet_params.delete(:network_uuid)
    end

    def network_params(vnet_params)
      vnet_params[:ipv4_network] = IPAddr.new(vnet_params[:ipv4_network], Socket::AF_INET).to_i
    end

    def interface_params(vnet_params)
      vnet_params[:mac_address] = ::Trema::Mac.new(vnet_params[:mac_address]).value
    end

    def ip_lease_params(vnet_params)
      interface_uuid = vnet_params.delete(:interface_uuid)
      interface = Vnet::NodeApi::Interface[interface_uuid]
      vnet_params[:mac_lease_id] = interface.mac_leases.first.id

      network_uuid = vnet_params.delete(:network_uuid)
      network = Vnet::NodeApi::Network[network_uuid]
      vnet_params[:network_id] = network.id

      vnet_params[:ipv4_address] = IPAddr.new(vnet_params[:ipv4_address], Socket::AF_INET).to_i
    end

    def translation_static_address_params(vnet_params)
      outer_network_gateway = find_gw_interface(vnet_params[:outer_network_uuid], vnet_params[:outer_network_gw])
      inner_network_gateway = find_gw_interface(vnet_params[:inner_network_uuid], vnet_params[:inner_network_gw])

      route_link = find_route_link(outer_network_gateway, inner_network_gateway)

      host_ports = Vnet::NodeApi::Interface.where(:mode=>'host').all
      host_ports.each do |host_port|
        Vnet::NodeApi::DatapathRouteLink.create({
          :datapath_id => host_port.active_datapath_id,
          :interface_id => host_port.id,
          :mac_address_id => mac_model_generate(datapath_route_link_prefix).id,
          :route_link_id => route_link.id
        })
      end

      translation = Vnet::NodeApi::Translation.create({
        :interface_id => inner_network_gateway.id,
        :mode => 'static_address',
        :passthrough => true
      })

      vnet_params[:route_link_id] = route_link.id

      ing = vnet_params[:ingress_ipv4_address]
      eg = vnet_params[:egress_ipv4_address]
      vnet_params[:ingress_ipv4_address] = IPAddr.new(ing).to_i
      vnet_params[:egress_ipv4_address] = IPAddr.new(eg).to_i

      vnet_params.delete(:outer_network_uuid)
      vnet_params.delete(:inner_network_uuid)
      vnet_params.delete(:outer_network_gw)
      vnet_params.delete(:inner_network_gw)
    end

    def simulated_interface_params(vnet_params)
      network = Vnet::NodeApi::Network[vnet_params[:network_uuid]]

      {
        :ipv4_address => IPAddr.new(vnet_params[:ipv4_address], Socket::AF_INET).to_i,
        :mac_address => ::Trema::Mac.new(vnet_params[:mac_address]).value,
        :mode => "simulated",
        :network_id => network && network.id
      }
    end

    def find_route(gw)
      Vnet::NodeApi::Route.find_all { |r| r.interface_id == gw.id }
    end

    def create_route(route_link, gw)
      #TODO
      params = {
        :interface_id => gw.id,
        :route_link_id => route_link.id,
        :network_id => gw.network.id,
        :ipv4_network => gw.network.ipv4_network,
        :ipv4_prefix => gw.network.ipv4_prefix
      }
      Vnet::NodeApi::Route.create(params)
    end

    def x
      "#{rand(16).to_s(16)}#{rand(16).to_s(16)}"
    end

    def mac_model_generate(prefix)
      Vnet::NodeApi::MacAddress.create({
        :mac_address => mac_generate(prefix)
      })
    end

    def mac_generate(prefix)
      mac = "#{prefix}:#{x}:#{x}:#{x}"
      ::Trema::Mac.new(mac).value
    end

    def create_route_link(gw_a, gw_b)
      route_link = Vnet::NodeApi::RouteLink.create({
        :mac_address_id => mac_model_generate(route_link_prefix).id
      })
      create_route(route_link, gw_a)
      create_route(route_link, gw_b)
      route_link
    end

    def find_route_link(gw_a, gw_b)
      r_a = find_route(gw_a)
      r_b = find_route(gw_b)

      route_link = find_pair(r_a, r_b)

      if route_link.nil?
        route_link = create_route_link(gw_a, gw_b)
      end

      route_link
    end

    def find_pair(r_a, r_b)
      r_a.each do |ra|
        r_b.each do |rb|
          return ra.route_link if ra.route_link.uuid == rb.route_link.uuid
        end
      end
      nil
    end

    def find_gw_interface(network_uuid, ipv4_gw)
      gateways = Vnet::NodeApi::Interface.find_all { |i|
        i.enable_routing == true && i.mode == 'simulated'
      }.select{ |i|
        i.network && i.network.canonical_uuid == network_uuid
      }

      if gateways.empty?
        warn "no gateway interface has been found in the network(#{network_uuid})"
        gateways << create_gw_interface(network_uuid, ipv4_gw)
      end

      if gateways.size > 1
        warn "multiple gateway interfaces have been detected in the network(#{network_uuid})"
      end

      gateways.first
    end

    def create_gw_interface(network_uuid, ipv4_gw)
      params = {
        :mode => 'simulated',
        :display_name => "gw_#{network_uuid}",
        :mac_address => mac_generate(gw_prefix),
        :enable_routing => true
      }
      interface = Vnet::NodeApi::Interface.create(params)
      network = Vnet::NodeApi::Network[network_uuid]

      ip_lease_params = {
        :ip_address_id => Vnet::NodeApi::IpAddress.create({:network_id => network.id, :ipv4_address => IPAddr.new(ipv4_gw).to_i}).id,
        :mac_lease_id => interface.mac_leases.first.id,
        :interface_id => interface.id,
        :enable_routing => true
      }
      Vnet::NodeApi::IpLease.create(ip_lease_params)

      interface
    end
  end
end

Vnet::Plugins::VdcVnetPlugin.supervise_as :vdc_vnet_plugin

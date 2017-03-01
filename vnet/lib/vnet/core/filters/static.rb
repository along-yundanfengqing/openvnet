# -*- coding: utf-8 -*-

module Vnet::Core::Filters
  class Static < Base2

    def initialize(params)
      super
      @statics = {}
    end

    def log_type
      'filter/static'
    end

    def install
      super

      flows = []

      @statics.each { |id, filter|
        debug log_format_h('installing filter', filter[:match])

        flows_for_static(flows, filter[:protocol], filter[:match], filter[:action])
      }

      @dp_info.add_flows(flows)
    end

    def added_static(params)
      static_id = get_param_id(params, :static_id)

      @statics[static_id] = {
        match: {
          static_id: static_id,
          ipv4_src_address: get_param_ipv4_address(params, :ipv4_src_address),
          ipv4_dst_address: get_param_ipv4_address(params, :ipv4_dst_address),
          ipv4_src_prefix: get_param_int(params, :ipv4_src_prefix),
          ipv4_dst_prefix: get_param_int(params, :ipv4_dst_prefix),
          port_src: get_param_int(params, :port_src, false),
          port_dst: get_param_int(params, :port_dst, false)
        },

        # TODO: Replace with symbol lookup.
        protocol: get_param_string(params, :protocol),
        action: get_param_string(params, :action)
      }.tap { |static|
        next if !installed?

        flows = []
        flows_for_static(flows, static[:protocol], static[:match], static[:action])

        @dp_info.add_flows(flows)
      }
    end

    def removed_static(params)
      @statics.delete(get_param_id(params, :static_id)).tap { |static|
        next if !installed? || static.nil?

        debug log_format_h('removing filter', static[:match])

        # TODO: Need to include priority when deleting.
        rules(static[:match], static[:protocol]).each { |egress_rule, ingress_rule|
          @dp_info.del_flows(table_id: TABLE_INTERFACE_INGRESS_FILTER,
            cookie: self.cookie,
            cookie_mask: Vnet::Constants::OpenflowFlows::COOKIE_MASK,
            match: ingress_rule)

          @dp_info.del_flows(table_id: TABLE_INTERFACE_EGRESS_FILTER,
            cookie: self.cookie,
            cookie_mask: Vnet::Constants::OpenflowFlows::COOKIE_MASK,
            match: egress_rule)
        }
      }
    end

    def packet_in(message)
      return if !installed?

      info log_format_h('packet_in', in_port: message.in_port, eth_dst: message.eth_dst, eth_src: message.eth_src)

      egress_match, ingress_match = match_from_message(message)
      return if egress_match.nil? || ingress_match.nil?

      info log_format_h('egress_match', egress_match)
      info log_format_h('ingress_match', ingress_match)

      flows = []

      flows << flow_create(table: TABLE_INTERFACE_EGRESS_FILTER,
                           goto_table: TABLE_INTERFACE_EGRESS_VALIDATE,
                           priority: 88,
                           match_interface: @interface_id,
                           match: egress_match)

      flows << flow_create(table: TABLE_INTERFACE_INGRESS_FILTER,
                           goto_table: TABLE_OUT_PORT_INTERFACE_INGRESS,
                           priority: 88,
                           match_interface: @interface_id,
                           match: ingress_match)

      @dp_info.add_flows(flows)
      @dp_info.send_packet_out(message, OFPP_TABLE)
    end

    #
    # Internal methods
    #

    private

    def rules(filter, protocol)
      ipv4_address = filter[:ipv4_dst_address]
      port = filter[:port_dst]
      prefix = filter[:ipv4_dst_prefix]

      case protocol
      when 'tcp'  then rule_for_tcp(ipv4_address, port, prefix)
      when 'udp'  then rule_for_udp(ipv4_address, port, prefix)
      when 'arp'  then rule_for_arp(ipv4_address, prefix)
      when 'icmp' then rule_for_icmp(ipv4_address, prefix)
      when 'all'  then rule_for_all(ipv4_address, prefix)
      end
    end

    def rule_for_tcp(ipv4_address, port, prefix)
      if port == 0 || port.nil?
        [
          [{ eth_type: ETH_TYPE_IPV4,
             ipv4_src: ipv4_address,
             ipv4_src_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_TCP,
           },
           { eth_type: ETH_TYPE_IPV4,
             ipv4_dst: ipv4_address,
             ipv4_dst_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_TCP,
           }]
        ]
      else
        [
          [{ eth_type: ETH_TYPE_IPV4,
             ipv4_src: ipv4_address,
             ipv4_src_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_TCP,
             tcp_src: port
           },
           { eth_type: ETH_TYPE_IPV4,
             ipv4_dst: ipv4_address,
             ipv4_dst_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_TCP,
             tcp_dst: port
           }]
        ]
      end
    end

    def rule_for_udp(ipv4_address, port, prefix)
      if port == 0 || port.nil?
        [
          [{ eth_type: ETH_TYPE_IPV4,
             ipv4_src: ipv4_address,
             ipv4_src_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_UDP,
           },
           { eth_type: ETH_TYPE_IPV4,
             ipv4_dst: ipv4_address,
             ipv4_dst_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_UDP,
           }]
        ]
      else
        [
          [{ eth_type: ETH_TYPE_IPV4,
             ipv4_src: ipv4_address,
             ipv4_src_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_UDP,
             udp_src: port
           },
           { eth_type: ETH_TYPE_IPV4,
             ipv4_dst: ipv4_address,
             ipv4_dst_mask: IPV4_BROADCAST << (32 - prefix),
             ip_proto: IPV4_PROTOCOL_UDP,
             udp_dst: port
           }]
        ]
      end
    end

    def rule_for_icmp(ipv4_address, prefix)
      [
        [{ eth_type: ETH_TYPE_IPV4,
           ipv4_src: ipv4_address,
           ipv4_src_mask: IPV4_BROADCAST << (32 - prefix),
           ip_proto: IPV4_PROTOCOL_ICMP
         },
         { eth_type: ETH_TYPE_IPV4,
           ipv4_dst: ipv4_address,
           ipv4_dst_mask: IPV4_BROADCAST << (32 - prefix),
           ip_proto: IPV4_PROTOCOL_ICMP
         }]
      ]
    end

    def rule_for_arp(ipv4_address, prefix)
      [
        [{ eth_type: ETH_TYPE_ARP,
           arp_spa: ipv4_address,
           arp_spa_mask: IPV4_BROADCAST << (32 - prefix)
         },
         { eth_type: ETH_TYPE_ARP,
           arp_tpa: ipv4_address,
           arp_tpa_mask: IPV4_BROADCAST << (32 - prefix)
         }]
      ]
    end

    def rule_for_all(ipv4_address, prefix)
      [
        [{ eth_type: ETH_TYPE_IPV4,
           ipv4_src: ipv4_address,
           ipv4_src_mask: IPV4_BROADCAST << (32 - prefix)
         },
         { eth_type: ETH_TYPE_IPV4,
           ipv4_dst: ipv4_address,
           ipv4_dst_mask: IPV4_BROADCAST << (32 - prefix)
         }]
      ]
    end

    def priority_for_static(prefix, port)
      20 + (prefix << 1) + ((port.nil? || port == 0) ? 0 : 1)
    end

    def flows_for_static(flows, protocol, filter, action)
      rules(filter, protocol).each { |ingress_rule, egress_rule|
        flow_base = {
          priority: priority_for_static(filter[:ipv4_dst_prefix], filter[:port_dst]),
          match_interface: @interface_id
        }

        if action == 'conn'
          flows << flow_create(flow_base.merge(table: TABLE_INTERFACE_EGRESS_FILTER,
                                               match: egress_rule,
                                               actions: { output: Vnet::Openflow::Controller::OFPP_CONTROLLER }))
          next
        end

        flows << flow_create(flow_base.merge(table: TABLE_INTERFACE_INGRESS_FILTER,
                                             goto_table: action == 'pass' ? TABLE_OUT_PORT_INTERFACE_INGRESS : nil,
                                             match: ingress_rule))

        flows << flow_create(flow_base.merge(table: TABLE_INTERFACE_EGRESS_FILTER,
                                             goto_table: action == 'pass' ? TABLE_INTERFACE_EGRESS_VALIDATE : nil,
                                             match: egress_rule))
      }
    end

    def match_from_message(message)
      egress_match = {
        eth_type: ETH_TYPE_IPV4,
        ipv4_src: message.ipv4_src,
        ipv4_dst: message.ipv4_dst
      }
      ingress_match = {
        eth_type: ETH_TYPE_IPV4,
        ipv4_src: message.ipv4_dst,
        ipv4_dst: message.ipv4_src
      }

      case
      when message.tcp?
        egress_match.merge!(ip_proto: IPV4_PROTOCOL_TCP,
                            tcp_src: message.tcp_src,
                            tcp_dst: message.tcp_dst)
        ingress_match.merge!(ip_proto: IPV4_PROTOCOL_TCP,
                             tcp_src: message.tcp_dst,
                             tcp_dst: message.tcp_src)
      when message.udp?
        egress_match.merge!(ip_proto: IPV4_PROTOCOL_UDP,
                            udp_src: message.udp_src,
                            udp_dst: message.udp_dst)
        ingress_match.merge!(ip_proto: IPV4_PROTOCOL_UDP,
                             udp_src: message.udp_dst,
                             udp_dst: message.udp_src)
      when message.icmpv4?
        egress_match.merge!(ip_proto: IPV4_PROTOCOL_ICMP)
        ingress_match.merge!(ip_proto: IPV4_PROTOCOL_ICMP)
      else
        return
      end

      return egress_match, ingress_match
    end

  end
end

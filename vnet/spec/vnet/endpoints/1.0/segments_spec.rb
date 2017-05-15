# -*- coding: utf-8 -*-
require 'spec_helper'
require 'vnet/endpoints/1.0/vnet_api'
Dir["#{File.dirname(__FILE__)}/shared_examples/*.rb"].map {|f| require f }
Dir["#{File.dirname(__FILE__)}/matchers/*.rb"].map {|f| require f }

def app
  Vnet::Endpoints::V10::VnetAPI
end

describe "/segments" do
  before(:each) { use_mock_event_handler }

  let(:api_suffix)  { "segments" }
  let(:fabricator)  { :segment }
  let(:model_class) { Vnet::Models::Segment }

  include_examples "GET /"
  include_examples "GET /:uuid"
  include_examples "DELETE /:uuid"

  describe "DELETE /:uuid event handler" do
    let!(:object) { Fabricate(fabricator) }
    let(:api_suffix_with_uuid) { "#{api_suffix}/#{object.canonical_uuid}" }

    it "handles a single event" do
      delete api_suffix_with_uuid
      expect(last_response).to succeed
      expect(MockEventHandler.handled_events.size).to eq 1
    end
  end

  describe "POST /" do
    let!(:topology) { Fabricate(:topology) { uuid 'topo-test' }  }

    accepted_params = {
      uuid: "seg-test",
      mode: "virtual",
      topology_uuid: 'topo-test'
    }
    expected_response = accepted_params.dup.tap { |map|
      map.delete(:topology_uuid)
    }
    required_params = [:mode]
    uuid_params = []

    include_examples "POST /", accepted_params, required_params, uuid_params, expected_response, Proc.new { |model, last_response|
      other_model = Vnet::Models::Topology[accepted_params[:topology_uuid]]
      other_model && Vnet::Models::TopologySegment[segment_id: model.id, topology_id: other_model.id]
    }

    context "With a wrong value for mode" do
      let(:request_params) { { mode: "klein soldaatje, groot soldaatje" } }

      it_should_return_error(400, "ArgumentError")
    end
  end
end

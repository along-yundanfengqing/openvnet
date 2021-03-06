# -*- coding: utf-8 -*-

shared_examples "api_with_uuid_in_suffix" do
  context "with a nonexistant uuid" do
    let(:api_suffix_with_uuid) { "#{api_suffix}/#{model_class.uuid_prefix}-notfound" }

    it "should return a 404 error (UnknownUUIDResource)" do
      expect(last_response).to fail.with_code(404).with_error("UnknownUUIDResource",
        /#{model_class.uuid_prefix}-notfound$/)
    end
  end

  context "with a uuid parameter with a faulty syntax" do
    let(:api_suffix_with_uuid) { "#{api_suffix}/this_aint_no_uuid" }

    it_should_return_error(400, "InvalidUUID", /this_aint_no_uuid$/)
  end
end

shared_examples "api_with_uuid_in_suffix_and_has_postfix" do
  context "with a nonexistant uuid" do
    let(:api_suffix_with_uuid) { "#{api_suffix}/#{model_class.uuid_prefix}-notfound/#{api_postfix}" }

    it "should return a 404 error (UnknownUUIDResource)" do
      expect(last_response).to fail.with_code(404).with_error("UnknownUUIDResource",
        /#{model_class.uuid_prefix}-notfound$/)
    end
  end

  context "with a uuid parameter with a faulty syntax" do
    let(:api_suffix_with_uuid) { "#{api_suffix}/this_aint_no_uuid/#{api_postfix}" }

    it_should_return_error(400, "InvalidUUID", /this_aint_no_uuid$/)
  end
end

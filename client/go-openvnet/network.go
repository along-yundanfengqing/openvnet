package openvnet

import (
	"net/http"
)

const NetworkNamespace = "networks"

type Network struct {
	ItemBase
	DisplayName string `json:"display_name"`
	Ipv4Network string `json:"ipv4_network"`
	Ipv4Prefix  int    `json:"ipv4_prefix"`
	Mode        string `json:"mode"`
	DomainName  string `json:"domain_name"`
	SegmentID   int    `json:"segment_id"`
}

type NetworkList struct {
	ListBase
	Items []Network `json:"items"`
}

type NetworkService struct {
	client *Client
}

type NetworkCreateParams struct {
	UUID        string `url:"uuid,omitempty"`
	DisplayName string `url:"display_name,omitempty"`
	Ipv4Network string `url:"ipv4_network"`
	Ipv4Prefix  int    `url:"ipv4_prefix,omitempty"`
	Mode        string `url:"mode"`
	DomainName  string `url:"domain_name,omitempty"`
	SegmentUUID string `url:"segment_id,omitempty"`
}

func (s *NetworkService) Create(params *NetworkCreateParams) (*Network, *http.Response, error) {
	nw := new(Network)
	resp, err := s.client.post(NetworkNamespace, nw, params)
	return nw, resp, err
}

func (s *NetworkService) Delete(id string) (*http.Response, error) {
	return s.client.del(NetworkNamespace + "/" + id)
}

func (s *NetworkService) Get() (*NetworkList, *http.Response, error) {
	list := new(NetworkList)
	resp, err := s.client.get(NetworkNamespace, list)
	return list, resp, err
}

func (s *NetworkService) GetByUUID(id string) (*Network, *http.Response, error) {
	nw := new(Network)
	resp, err := s.client.get(NetworkNamespace+"/"+id, nw)
	return nw, resp, err
}

| filter( dataSource.name == "FortiGate" AND event.type == "traffic" ) 
| group PortCount = count() by dst_endpoint.port, src_endpoint.svc_name 
| sort - PortCount 
| limit 1000
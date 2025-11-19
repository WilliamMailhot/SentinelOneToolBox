| filter( dataSource.name == "FortiGate" AND event.type == "traffic" ) 
| columns src_endpoint.ip, src_endpoint.intermediate_ips\[0\], dst_endpoint.ip, dst_endpoint.location.country 
| group EventCount = count() by src_endpoint.ip, src_endpoint.intermediate_ips\[0\], dst_endpoint.ip, dst_endpoint.location.country 
| sort -EventCount 
| limit 1000
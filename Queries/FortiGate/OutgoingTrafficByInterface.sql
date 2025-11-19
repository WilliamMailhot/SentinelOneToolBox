| parse "$bytes_out{regex=\\d+}$" from unmapped.sentdelta 
| filter( dataSource.name == "FortiGate" AND event.type == "traffic" ) 
| group TotalBytesOut = sum(bytes_out) by dst_endpoint.interface_name 
| columns dst_endpoint.interface_name, TotalBytesOut 
| sort - TotalBytesOut 
| limit 1000
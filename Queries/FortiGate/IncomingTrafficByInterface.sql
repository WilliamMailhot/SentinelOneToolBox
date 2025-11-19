| parse "$bytes_in{regex=\\d+}$" from unmapped.rcvddelta
| filter( dataSource.name == "FortiGate" AND event.type == "traffic" ) 
| group TotalBytesIn = sum(bytes_in) by dst_endpoint.interface_name 
| columns dst_endpoint.interface_name, TotalBytesIn 
| sort - TotalBytesIn
| limit 1000
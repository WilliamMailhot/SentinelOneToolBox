| parse "$bytes_out{regex=\\d+}$" from unmapped.sentdelta 
| filter( dataSource.name == "FortiGate" ) 
| group TotalBytesOut = sum(bytes_out) by src_endpoint.ip  
| columns src_endpoint.ip , TotalBytesOut 
| sort - TotalBytesOut 
| limit 10
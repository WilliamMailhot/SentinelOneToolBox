event.url.action='GET'  src.process.displayName in ('Google\ Chrome', 'Microsoft\ Edge', 'Firefox') 
| parse "https://$domain{regex=[^/]+}$" from url.address
| group domainCount = count() by domain
| sort - domainCount
| limit 100
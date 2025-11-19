dataSource.vendor='Microsoft' event.type = 'UserLoginFailed' AND actor.user.email_addr != null
| parse '"ClientIP": "$IP$"' 
| let User=actor.user.email_addr
| group LoginCount = count() by User, geo_ip_country(IP), IP
| sort - LoginCount
| limit 200
| sql join baseline = (
dataSource.vendor='Microsoft' event.type='Logon'
| columns actor.user.email_addr, src_endpoint.ip, geo_ip_state(src_endpoint.ip)
| group login_freq_by_state=count() by email_addr=lower(actor.user.email_addr),state=geo_ip_state(src_endpoint.ip)
| columns email_addr,state,login_freq_by_state
| sort +email_addr,-login_freq_by_state
| group baseline_login_freq_by_state=max(login_freq_by_state), states=array_agg(state) by email_addr
| filter email_addr!=""
| columns email_addr,state=array_get(states,0),baseline_login_freq_by_state
),
logons = (
dataSource.vendor='Microsoft' event.type='Logon'
| group deviation_login_count=count(event.type),deviation_ip_addresses=array_agg_distinct(src_endpoint.ip) by email_addr=lower(actor.user.email_addr), deviation_country=geo_ip_country(src_endpoint.ip), state=geo_ip_state(src_endpoint.ip)
) on baseline.email_addr==logons.email_addr
|filter baseline.state!=logons.state
| columns email_addr,baseline.state, baseline_login_freq_by_state,deviation_login_source=format("%s (%s)",logons.state,deviation_country),deviation_login_count, deviation_ip_addresses
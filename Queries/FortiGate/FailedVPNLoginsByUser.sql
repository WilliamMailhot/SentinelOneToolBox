| filter( dataSource.name == "FortiGate" AND unmapped.msg='SSL user failed to logged in' ) 
| group FailedLoginCount = count() by unmapped.user 
| sort - FailedLoginCount
event.login.loginIsSuccessful=true event.login.type='UNLOCK'
| group loginCount = count() by event.login.userName
| sort - loginCount
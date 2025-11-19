event.type='Task\ Start' tgt.file.name='powershell.exe'
| group topTasks = count() by task.name
| sort - topTasks
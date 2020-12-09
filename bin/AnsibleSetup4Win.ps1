mkdir C:\temp
Invoke-WebRequest -Uri https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1 -outfile ConfigureRemotingForAnsible.ps1
cd C:\temp
.\ConfigureRemotingForAnsible.ps1
winrm enumerate winrm/config/Listener
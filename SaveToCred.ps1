# Requires the CredentialManager module
Install-Module -Name CredentialManager -Scope CurrentUser -Force

# Save the token
New-StoredCredential -Target "DPA-API-svwpapl03" `
                     -UserName "api-service" `
                     -Password "eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJkcGExIiwic3ViIjoiQVBJLVRPS0VOIiwiaWF0IjoxNzc3MjkzOTA2LCJzYW1sVXNlciI6ZmFsc2V9.Gg" `
                     -Persist LocalMachine
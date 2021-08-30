# AWS Server Automation Script

## FILE INFO
instanceSetup.sh : This is the script you run to instantiate the EC2 instance and configure the webserver

automateServer.sh : This is the script that gets deployed to the EC2 instance by instanceSetup.sh and is automatically run to configure the webserver

secureDomains.sh : This is the script you run to setup LetsEncrypt on the webserver

certifyDomains.sh : This is the script that gets deployed to the EC2 instance by secureDomains.sh and is automatically run to configure LetsEncrypt for the domains you specified


## Server Automation Script Instructions
Before starting, ensure that AWS CLI is installed on the command line and that your AWS account is linked to it.

1) Run instanceSetup.sh first with the following syntax: ./instanceSetup.sh -t [instance type here] -k [key name here] -d [domain name]. If you're using an existing key make sure that it's in the same directory as the rest of the files!!!

2) Once instanceSetup.sh is finished running, make sure to keep the info and command that it gives at the end.  You'll need the listed IP address for the next step.

3) Go to your domain registrar of choice and set up your domains to point at the IP address that was listed at the end of instanceSetup.sh.

4) Once your domains are properly configured, run the command that you were given at the end of instanceSetup.sh. It should look similar to ./secureDomains.sh -i [instanceID] -d [domain]. You may have more than one -d flag if you added multiple domains. 

5) If you go to your domain in the web browser, you should see a WordPress installation page. Once you go through that process, you should have a brand new WordPress website ready to be personalized!

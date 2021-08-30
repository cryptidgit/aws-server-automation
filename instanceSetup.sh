#!/bin/bash

######################################################################################
# OPTION PROCESSING

while getopts "hs:t:k:m:n:d:" option; do
  case $option in
    h) # Display options with explanations 
       echo ""
       echo ""
       echo ""
       echo "instanceSetup syntax: instanceSetup [-h|s|m|n] -t instanceType -k KeyName"
       echo ""
       echo "Options:"
       echo "-h Display script options"
       echo "-s Set security group id"
       echo "-t Specify instance type"
       echo "-k Create new key or use existing one"
       echo "-m Set disk size for instance (in GiB)"
       echo "-n Set instance name"
       echo "-d Add domains to run server setup script"
       echo ""
       echo ""
       echo ""
       exit
       ;;
    
    s) # Set security group id
       securityID=$OPTARG
       ;;

    t) # Set instance type
       instance=$OPTARG
       ;;

    k) # Add key variable
       key=$OPTARG
       ;;

    m) # Set disk size 
       disksize=$OPTARG
       ;;

    n) # Set instance name
       name=$OPTARG
       ;;

    d) # Hold domain names
       domains+=(-d $OPTARG)
       ;;

   \?) # Handle invalid options
       echo "See instanceSetup -h for help"
       exit
       ;;
  esac
done

  
#######################################################################################

# Exit script if key and instance type aren't provided
if [[ $* != *-t* ]] && [[ $* != *-k* ]];
then
  echo "Error: Missing instance type or key pair"
  exit
fi

# Add optional variables to array
if [[ ! -z "$securityID" ]];
then
  args+=(--security-group-ids $securityID)
elif [ $(aws ec2 describe-security-groups | grep -c "defaultSecurityGroup") -eq 0 ];
then
  myip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
  aws ec2 create-security-group --group-name defaultSecurityGroup --description "Default security group settings to access server" 
  aws ec2 authorize-security-group-ingress --group-name defaultSecurityGroup --protocol tcp --port 443 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-name defaultSecurityGroup --protocol tcp --port 80 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-name defaultSecurityGroup --protocol tcp --port 22 --cidr $myip/32

  args+=(--security-groups defaultSecurityGroup)
elif [ $(aws ec2 describe-security-groups | grep -c "defaultSecurityGroup") -eq 1 ];
then
  args+=(--security-groups defaultSecurityGroup)
fi

if [[ ! -z "$disksize" ]];
then
  args+=(--block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$disksize}")
fi


if [[ ! -z "$name" ]];
then 
  args+=(--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name}]")
fi

if [[ $(aws ec2 describe-key-pairs | grep -c "$key") -eq 0  ]];
then
  aws ec2 create-key-pair --key-name $key --query 'KeyMaterial' --output text > "$key.cer"
  chmod 600 "$key.cer"
fi

# Set up instance with specifications
aws ec2 run-instances --image-id ami-09e67e426f25ce0d7 --instance-type $instance --key-name $key "${args[@]}" | grep -q "hello"

echo "Waiting for instance to be set up..."
# Wait for public IP to be created
percent=0
for i in {1..10}
  do  
    percent=$((percent+10))
    echo "$percent%"
    sleep 4.5 
done 

aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output=text > tempfile

#instanceid=$(tail -2 tempfile | grep "i-0" | tr -d '""')
instanceid=$(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output=text | awk 'NF>1{print $NF}')
ipaddress=$(aws ec2 describe-instances --instance-ids $instanceid --query "Reservations[*].Instances[*].PublicIpAddress" --output=text)
publicdns=$(aws ec2 describe-instances --instance-ids $instanceid --query "Reservations[*].Instances[*].PublicDnsName" --output=text)

rm tempfile

# Upload server automation script to instance
echo "Uploading automateServer.sh to instance..."
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$key.cer" automateServer.sh ubuntu@$publicdns:~/

echo "Uploading certifyDomains.sh to instance..."
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$key.cer" certifyDomains.sh ubuntu@$publicdns:~/


if [[ -z "$domains" ]];
then
  exit
fi

if [[ ! -f "ec2-role-trust-policy.json" ]];
then
  cat >> ec2-role-trust-policy.json <<EOL
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": { "Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }
    ]
  }
EOL
fi
 

# Set up remote commands to instance
if [ $(aws iam list-roles | grep -c "EC2RemoteCommand") -eq 0 ];
then
  aws iam create-role --role-name EC2RemoteCommand --assume-role-policy-document file://ec2-role-trust-policy.json
  aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM --role-name EC2RemoteCommand
  aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess --role-name EC2RemoteCommand
fi

if [ $(aws iam list-instance-profiles | grep -c "NewRole-Instance-Profile") -eq 0 ];
then
  aws iam create-instance-profile --instance-profile-name NewRole-Instance-Profile
  aws iam add-role-to-instance-profile --role-name EC2RemoteCommand --instance-profile-name NewRole-Instance-Profile
fi

aws ec2 associate-iam-instance-profile --instance-id $instanceid --iam-instance-profile Name=NewRole-Instance-Profile

aws ec2 wait instance-running --instance-ids $instanceid

echo "Waiting for SSM..."

while [ $(aws ssm describe-instance-information --output text | grep -c "$instanceid") -eq 0 ]
do
  continue
done

aws ssm send-command --document-name "AWS-UpdateSSMAgent" --document-version "1" --instance-ids "$instanceid" --parameters '{"version":[""],"allowDowngrade":["false"]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --output-s3-bucket-name "ry-s3-bucket" --region us-east-1

# Run automateServer.sh
aws ssm send-command --document-name "AWS-RunShellScript" --instance-ids "$instanceid" --parameters commands="[\"cd /home/ubuntu\",\"bash automateServer.sh ${domains[*]}\"]" --output-s3-bucket-name "ry-s3-bucket" --region us-east-1

echo "After pointing your domain records to the server IP of: $ipaddress, run this command to setup the LetsEncrypt SSL certificates: ./secureDomains.sh -i $instanceid ${domains[*]}"
# aws ssm send-command --document-name "AWS-RunShellScript" --document-version "1" --instance-ids "$instanceid" --parameters '{"workingDirectory":[""],"executionTimeout":["3600"],"commands":["cd /home/ubuntu","bash automateServer.sh ${domains[@]}"]}' --timeout-seconds 600 --max-concurrency "50" --max-errors "0" --output-s3-bucket-name "ry-s3-bucket" --region us-east-1

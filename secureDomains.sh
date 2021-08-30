#!/bin/bash

###################################################################################
# OPTION PROCESSING

while getopts "hi:d:" option; do
  case $option in
    h) # Display options with explanations
      echo ""
      echo ""
      echo ""
      echo "secureDomains syntax: secureDomains [-h] -i instanceID -d domain"
      echo ""
      echo "Options:"
      echo "-h Display secureDomains options"
      echo "-i Specify instance ID to run script"
      echo "-d Specify one or more domains"
      echo ""
      echo ""
      echo ""
      exit
      ;;
    
    i) # Specify instance ID
       instanceid=$OPTARG
       ;;

    d) # Domains to receive SSL certificate
       domains+=(-d $OPTARG)
       ;;

   \?) # Handle invalid options
       echo "See secureDomains -h for help"
       exit
       ;;
  esac
done
#####################################################################################

if [[ $* != *-d* ]] || [[ $* != *-i* ]];
then 
  echo "Syntax error: bash secureDomains.sh -i instanceID -d domain"
  exit
fi

aws ssm send-command --document-name "AWS-RunShellScript" --instance-ids "$instanceid" --parameters commands="[\"cd /home/ubuntu\",\"bash certifyDomains.sh ${domains[*]}\"]" --output-s3-bucket-name "ry-s3-bucket" --region us-east-1


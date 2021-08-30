#!/bin/bash

###################################################################################
# OPTION PROCESSING

while getopts "hmd:" option; do
  case $option in
    h) # Display options with explanations
      echo ""
      echo ""
      echo ""
      echo "certifyDomains syntax: certifyDomains [-h|m] -d domain"
      echo ""
      echo "Options:"
      echo "-h Display certifyDomains options"
      echo "-m Specify email for certBot to contact"
      echo "-d Specify one or more domains"
      echo ""
      echo ""
      echo ""
      exit
      ;;

    d) # Domains to receive SSL certificate
       domains+=(-d $OPTARG)
       ;;

    m) # Add email variable
       mail=$OPTARG
       ;;

   \?) # Handle invalid options
       echo "See certifyDomains -h for help"
       exit
       ;;
  esac
done
####################################################################################

if [ -z $email ];
then
  email=hosting@4sitestudios.com
fi

if [[ $* != *-d* ]];
then 
  echo "Syntax error: bash certifyDomains.sh -d domain"
  exit
fi

if [ $(sudo certbot certificates | grep -c "Found the following certs") -eq 0 ];
then
  sudo certbot --noninteractive --nginx --agree-tos ${domains[*]} -m $email
fi


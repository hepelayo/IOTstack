#!/bin/bash

# Configure Traefik

function configTraefik(){
    # Create the file where the certs will be saved if not exists
    [ ! -d ./certs ] && mkdir ./certs
    [ -f ./certs/acme.json ] && rm ./certs/acme.json
    touch ./certs/acme.json && chmod 600 ./certs/acme.json
    echo -e "\e[93m""Created certificates folder""\e[0m"

    # Setup the traefik.env file
    clear
    whiptail --title "Traefik Let's Encrypt" --msgbox "Let's start configuring your DuckDNS account" 10 60 3>&1 1>&2 2>&3
    duckToken=$(whiptail --title "DuckDNS account" --inputbox "Please enter your DuckDNS Token:" 10 60 3>&1 1>&2 2>&3)
    duckSubdomain=$(whiptail --title " DuckDNS account" --inputbox "Please enter your DuckDNS Subdomain:" 10 60 3>&1 1>&2 2>&3)
    whiptail --title "Traefik Dashboard Access" --msgbox "Next we will configure the access to the Traefik Dashboard" 10 60 3>&1 1>&2 2>&3
    traefikUsername=$(whiptail --title "Traefik Dashboard account" --inputbox "Please enter the desired username to access to the dashboard:" 10 60 3>&1 1>&2 2>&3)
    
    if [ ! -z "$traefikUsername" ];then
        while [[ "$passphrase" != "$passphrase_repeat" || ${#passphrase} -lt 8 ]]; do
    		passphrase=$(whiptail --title "Traefik Dashboard account" --passwordbox "${passphrase_invalid_message}Please enter the passphrase (8 chars min.):" 10 60 3>&1 1>&2 2>&3)
	    	passphrase_repeat=$(whiptail --title "Traefik Dashboard account" --passwordbox "Please repeat the passphrase:" 10 60 3>&1 1>&2 2>&3)
		    passphrase_invalid_message="Passphrase too short, or not matching! "
	    done
	    #traefikUserPass=$(echo $passphrase | htpasswd -ni $traefikUsername)
        traefikUserPass=$traefikUsername:`echo $passphrase | openssl passwd -apr1 -stdin`
        if [ ! -z "$traefikUserPass" ]; then
            if [[ $(grep -cs "TRAEFIK_HTTP_USERPASS=" .env) -gt 0 ]]; then
                sed --in-place -r "s/^(TRAEFIK_HTTP_USERPASS=).*/\1$traefikUserPass/" .env
            else
                echo "TRAEFIK_HTTP_USERPASS=$traefikUserPass" >> .env
            fi
            sed --in-place -r "s/^#(      - traefik.frontend.auth.basic.users\.*)/\1/" ./docker-compose.yml
        else
            sed --in-place -r "s/^(      - traefik.frontend.auth.basic.users\.*)/#\1/" ./docker-compose.yml
        fi
    else
        echo -e "Username not entered. This disable basic HTML authentication in Traefik Dashboard..."
        sed --in-place -r "s/^(      - traefik.frontend.auth.basic.users\.*)/#\1/" ./docker-compose.yml
    fi
    echo -e "\e[93m""Added basic authentication to Traefik Dashboard""\e[0m"

    if [ ! -z "$duckToken" -a ! -z "$duckSubdomain" ]; then
        sed --in-place -r "s/^(DUCKDNS_TOKEN=).*/\1$duckToken/" ./services/traefik/traefik.env
        
        # Setup crontab to update the Raspberry Pi IP in DuckDNS
        sed --in-place -re "s/^(DOMAINS=).*/\1$duckSubdomain/; s/^(DUCKDNS_TOKEN=).*/\1$duckToken/" ./duck/duck.sh
        echo "*/5 * * * * root /home/pi/IOTstack/duck/duck.sh" | sudo tee /etc/cron.d/duckdns_cron &>/dev/null
        echo -e "\e[93m""Added DuckDNS IP updater to Crontab (/etc/cron.d/duckdns_cron)""\e[0m"

        # Set .env file in docker-compose directory in order to easy the traefik's labels config
        if [[ $(grep -cs "DOMAIN_NAME=" .env) -gt 0 ]]; then
            sed --in-place -r "s/^(DOMAIN_NAME=).*/\1$duckSubdomain.duckdns.org/" .env
        else
            echo "DOMAIN_NAME=$duckSubdomain.duckdns.org" >> .env
        fi
    fi  
    
    touch ./services/traefik/.settedup
}

#Check if has been previously configured
if [ ! -f ./services/traefik/.settedup ]; then
    configTraefik  
else
    if (whiptail --title "Traefik Configuration detected" --yesno "A Traefik configuration has been detected. Do you want to overwrite it?" 20 78); then
		configTraefik
	fi
fi

# Dump Traefik certificates to key, crt and pem files
if [ "$(stat -c %s "./certs/acme.json")" -gt 0 ]; then
        .certsDumper/traefik-certs-dumper.sh
fi

# Add crontab to update the dumped certificates if Traefik certicate has changed
echo "0 0 * * * root /home/pi/IOTstack/certsDumper/traefik-certs-dumper.sh >/dev/null 2>&1" | sudo tee /etc/cron.d/traefik-certs-dumper_cron &>/dev/null

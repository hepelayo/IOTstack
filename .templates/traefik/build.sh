#!/bin/bash

# Configure Traefik

function configTraefik(){
    # Create the file where the certs will be saved if not exists
    [ -f ./services/traefik/acme.json ] && rm ./services/traefik/acme.json
    touch ./services/traefik/acme.json && chmod 600 ./services/traefik/acme.json

    # Setup the traefik.env file
    clear
    echo -e "Let's start configuring your DuckDNS account"
    read -p "  Enter your DuckDNS Token: " duckToken
    read -p "  Enter your DuckDNS subdomian : " duckSubdomain
    echo
    echo -e "Next we will configure the access to the Traefik Dashboard"
    read -p "  Enter the desired username to access to the dashboard: " traefikUsername

    if [ ! -z "$traefikUsername" ];then
        traefikPassword=$(htpasswd -n $traefikUsername | cut -d ':' -f2)
        if [ ! -z "$traefikPassword" ]; then
            if [[ $(grep -cs "TRAEFIK_HTTP_USERNAME=" .env) -gt 0 ]]; then
                sed --in-place -re "s/^(TRAEFIK_HTTP_USERNAME=).*/\1$traefikUsername/" .env
            else
                echo "TRAEFIK_HTTP_USERNAME=$traefikUsername" >> .env
            fi
            if [[ $(grep -q "TRAEFIK_HTTP_PASSWORD=" .env) -gt 0 ]]; then
                sed --in-place -re "s/^(TRAEFIK_HTTP_PASSWORD=).*/\1$traefikPassword/" .env
            else
                echo "TRAEFIK_HTTP_PASSWORD=$traefikPassword" >> .env
            fi            
            sed --in-place -re "s/^#(      - traefik.frontend.auth.basic.users\.*)/\1/" ./docker-compose.yml
        else
            sed --in-place -re "s/^(      - traefik.frontend.auth.basic.users\.*)/#\1/" ./docker-compose.yml
        fi
    else
        echo -e "Username not entered. This disable basic HTML authentication in Traefik Dashboard..."
        sed --in-place -re "s/^(      - traefik.frontend.auth.basic.users\.*)/#\1/" ./docker-compose.yml
    fi
    

    if [ ! -z "$duckToken" -a ! -z "$duckSubdomain" ]; then
        sed --in-place -re "s/^(DUCKDNS_TOKEN=).*/\1$duckToken/" ./services/traefik/traefik.env
        
        # Setup crontab to update the Raspberry Pi IP in DuckDNS
        sed --in-place -re "s/^(DOMAINS=).*/\1$duckSubdomain/; s/^(DUCKDNS_TOKEN=).*/\1$duckToken/" ./duck/duck.sh
        echo "*/5 * * * root ${PWD}/duck/duck.sh" | sudo tee /etc/cron.d/duckdns_cron &>/dev/null

        # Set .env file in docker-compose directory in order to easy the traefik's labels config
        if [[ $(grep -cs "DOMAIN_NAME=" .env) -gt 0 ]]; then
            sed --in-place -re "s/^(DOMAIN_NAME=).*/\1$duckSubdomain.duckdns.org/" .env
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
#!/bin/bash
wipe=$'\e[0m'
yellow=$'\e[93m'

Update() {
  clear
  echo -e "$yellow""Updating..." "$wipe"
  sudo apt-get update -y
  echo -e "$yellow"
  echo -e "Upgrading..." "$wipe"
  sudo apt-get upgrade -y
}

Disable_ipv6() {
  if [[ $(grep -cs "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf) -eq 0 ]]; then
    echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee /etc/sysctl.conf &>/dev/null
    sudo sysctl -p
    else
    echo "IPv6 is already disabled"
  fi
}

InstallSamba() {
  if [ -f /etc/samba/smb.conf ]
    then
      echo "Samba already installed..."
    else
      echo -e "$yellow""Setting up Samba..." "$wipe"
      sudo apt install samba samba-common-bin -y
  fi

  grep -q "\[${PWD##*/}\]" /etc/samba/smb.conf
  if [ $? -eq 0 ]
    then
      echo -e "$yellow""Current directory is already shared...""$wipe"
    else
      echo -e "$yellow""Writting samba config file to share current directory...""$wipe"
      echo -e "\n[${PWD##*/}]\n   path=${PWD}\n   valid users = ${USER}\n   force group = $(id -gn ${USER})\n   create mask = 0644\n   directory mask = 0755\n   read only = no" | sudo tee -a /etc/samba/smb.conf > /dev/null
  fi
  
  echo -e "$yellow""Adding 'pi' user to samba..." "$wipe"
  sudo smbpasswd -a pi

  echo -e "$yellow""Restarting Samba service..." "$wipe"
  sudo service smbd restart

  #id -u fsdf &> /dev/null; if [ $? -eq 1 ]; then echo "no existe"; else echo "existe"; fi
  # passwort='Passwort halt'
  # benutzername='Benutzername'
  # useradd -m $benutzername
  # (echo "password"; sleep 5; echo "password";) | passwd $benutzername
  # (echo $passwort; sleep 5; echo $passwort ) | smbpasswd -s -a $benutzername

  #-comprobar si usuario existe en Samba
  #sudo pdbedit -u pi $>/dev/null; if [ $? -eq 0 ]; then echo "existe"; else echo "no existe"; fi
}

InstallDuckDNSCronTab() {
  whiptail --title "DuckDNS Crontab Setup" --msgbox "A continuación configuraremos el servicio que actualizará cada 5 minutos el redireccionamiento hacia nuestra IP de los dominios registrados en 'www.duckdns.org'." 10 78
  DOM=$(whiptail --title "DuckDNS Crontab Setup" --inputbox "Introduce la lista de dominios registrados en DuckDNS separados por coma sin espacio:" 8 78  3>&1 1>&2 2>&3)
  TOK=$(whiptail --title "DuckDNS Crontab Setup" --inputbox "Introduce el token generado por DuckDNS:" 20 50 3>&1 1>&2 2>&3) 
  echo -e "#!/bin/bash" > ./duckdns.sh
  echo -e "DOMAINS=$DOM" >> ./duckdns.sh
  echo -e "TOKEN=$TOK" >> ./duckdns.sh 
  echo 'echo url="https://www.duckdns.org/update?domains=$DOMAINS&token=$TOKEN&ip=" | curl -k -o ~/duckdns.log -K -' >> ./duckdns.sh
  sudo chmod 700 ./duckdns.sh
  #create new cron file into cron directory
  echo "*/5 * * * $USER ${PWD}/duckdns.sh" | sudo tee /etc/cron.d/duckdns_cron &>/dev/null
}

function command_exists() {
	command -v "$@" >/dev/null 2>&1
}

InstallDocker() {
  if command_exists docker; then
		echo -e "$yellow"
    echo -e "Docker already installed""$wipe"
	else
		echo -e "$yellow"
    echo -e "Install Docker...""$wipe"
		curl -fsSL https://get.docker.com | sh
		sudo usermod -aG docker $USER
	fi

	if command_exists docker-compose; then
		echo -e "$yellow"
    echo -e "Docker-compose already installed""$wipe"
	else
		echo -e "$yellow"
    echo -e "Install docker-compose""$wipe"
		sudo apt install -y docker-compose
	fi

	if (whiptail --title "Restart Required" --yesno "It is recommended that you restart you device now. Select yes to do so now" 20 78); then
		sudo reboot
	fi
}

mainmenu_selection=$(whiptail --title "Main Menu" --menu --notags \
	"" 20 78 12 -- \
  "all" "Install all" \
  "disableipv6" "Disable IPv6" \
  "update" "Update Raspberry Pi" \
  "samba" "Install Samba" \
  3>&1 1>&2 2>&3)
  #"duckdns" "Install Dinamic DNS updater (for DuckDNS)" \
	#"docker" "Install Docker" \
  #"build" "Build Stack" \
	#"hassio" "Install Hass.io (Requires Docker)" \
	#"commands" "Docker commands" \
	#"backup" "Backup options" \
	#"misc" "Miscellaneous commands" \
	

case $mainmenu_selection in
  "all")
    Disable_ipv6 
    Update
    InstallSamba
    #InstallDuckDNSCronTab
    #InstallDocker
    ;;
  "disableipv6")
    Disable_ipv6
    ;;
  "update")
    Update
    ;;
  "samba")
    InstallSamba
    ;;
  "duckdns")
    InstallDuckDNSCronTab
    ;;
  "docker")
    InstallDocker
    ;;
  *)
    ;;
esac
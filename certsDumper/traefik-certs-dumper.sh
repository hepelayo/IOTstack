#!/bin/bash

#----------------------------------------------------------------------------------------------------
# Variables
#----------------------------------------------------------------------------------------------------

# Location of the traefik-certs-dumper script, written by LDEZ <https://github.com/ldez/traefik-certs-dumper>
CERT_DUMP_SCRIPT="/bin/traefik-certs-dumper"

# Temp directory to write all exported certificates to (unfortunately the script from ldez doesn't support to export 'just one' domain.) - will be removed at the end of the script.
CERT_DUMP_DIR="/home/pi/IOTstack/tmp"

# Location of the Traefik generated acme.json file
TRAEFIK_ACME_FILE="/home/pi/IOTstack/certs/acme.json"

# My docker container and hostname to look for
MQTT_DOCKER_CONTAINER="mosquitto"
MQTT_HOSTNAME="olimpohome.duckdns.org"

# The location of where to save the certificates
MQTT_CERT_DIR="/home/pi/IOTstack/certs"

# Ensure the certificates eventually have this file ownership
MQTT_CERT_OWNERSHIP="pi:pi"

#----------------------------------------------------------------------------------------------------
# Start script (no changed needed below)
#----------------------------------------------------------------------------------------------------

# Check if certificate dump script exists
if [ ! -f "$CERT_DUMP_SCRIPT" ]; then
	echo "ERROR: The 'traefik-certs-dumper' script doesn't exist: $CERT_DUMP_SCRIPT."
	echo "Trying to download it."
	curl -sfL https://raw.githubusercontent.com/ldez/traefik-certs-dumper/master/godownloader.sh | bash -s -- -b $GOPATH/bin v1.5.0
	if [ ! -f "$CERT_DUMP_SCRIPT" ]; then
		echo "ERROR: The 'traefik-certs-dumper' script doesn't exist: $CERT_DUMP_SCRIPT."
		exit 1
	fi
fi

# Check if the Traefik ACME file exists
if [ ! -f "$TRAEFIK_ACME_FILE" ]; then
	echo "ERROR: The Traefik acme file doesn't exist: $TRAEFIK_ACME_FILE."
	exit 1
fi

# Check if container exists
if [[ $(docker ps --filter "name=^/$MQTT_DOCKER_CONTAINER$" --format '{{.Names}}') != $MQTT_DOCKER_CONTAINER ]]; then
	echo "ERROR: The docker container doesn't seem to exist: $MQTT_DOCKER_CONTAINER."
	exit 1
fi


# Check if certificate directory exists
if [ ! -d "$MQTT_CERT_DIR" ]; then
	echo "ERROR: The location of the certificates doesn't seem to exist: $MQTT_CERT_DIR."
	exit 1
fi

# Run the certificate dump script
$CERT_DUMP_SCRIPT dump --source $TRAEFIK_ACME_FILE --domain-subdir=true --dest $CERT_DUMP_DIR >> /dev/null 2>&1
curl -sfL https://letsencrypt.org/certs/trustid-x3-root.pem > $CERT_DUMP_DIR/letsencrypt.pem
ERROR=$?
if [ $ERROR -eq 0 ]; then
	# Verify the certificate and the key
	CERT_EXPORTED=$CERT_DUMP_DIR/$MQTT_HOSTNAME/certificate.crt
	if [ ! -f "$CERT_EXPORTED" ]; then
		echo "ERROR: Unable to find the configured certificate in the export: $CERT_EXPORTED."
		ERROR=1
	fi

	KEY_EXPORTED=$CERT_DUMP_DIR/$MQTT_HOSTNAME/privatekey.key
	if [ ! -f "$KEY_EXPORTED" ]; then
		echo "ERROR: Unable to find the configured privatekey in the export: $KEY_EXPORTED."
		ERROR=1
	fi

	CA_DOWNLOADED=$CERT_DUMP_DIR/letsencrypt.pem
	if [ ! -f "$CA_DOWNLOADED" ]; then
		echo "ERROR: Unable to find the configured CA file in the export: $CA_DOWNLOADED."
		ERROR=1
	fi

	# Can we still continue?
	if [ $ERROR -eq 0 ]; then
		CERT_EXISTING=$MQTT_CERT_DIR/certificate.crt
		CERT_COPY=0
		if [ ! -f "$CERT_EXISTING" ]; then
			# Copy the exported certificate to the MQTT certificate directory if it doesn't exist yet.
			echo "Notice: Copying exported certificate since certificate doesn't exist yet..."
			CERT_COPY=1
		else
			# Verify if the exported certificate needs to be copied to the MQTT certificate directory
			diff --binary --brief $CERT_EXPORTED $CERT_EXISTING > /dev/null 2>&1
			if [ $? -eq 1 ]; then
				echo "Notice: Updating existing certificate since exported certificate is different..."
				CERT_COPY=1
			fi
		fi

		if [ $CERT_COPY -eq 1 ]; then
			echo "- Copying $CERT_EXPORTED to $CERT_EXISTING ..."
			cp $CERT_EXPORTED $CERT_EXISTING
			if [ $? -eq 0 ]; then
				echo "- Updating file ownership of $CERT_EXISTING ..."
				sudo chown $MQTT_CERT_OWNERSHIP $CERT_EXISTING
			fi
		fi

		KEY_EXISTING=$MQTT_CERT_DIR/privatekey.key
		KEY_COPY=0
		if [ ! -f "$KEY_EXISTING" ]; then
			# Copy the exported privatekey to the MQTT certificate directory if it doesn't exist yet.
			echo "Notice: Copying exported privatekey since privatekey doesn't exist yet..."
			KEY_COPY=1
		else
			# Verify if the exported privatekey needs to be copied to the MQTT certificate directory
			diff --binary --brief $KEY_EXPORTED $KEY_EXISTING > /dev/null 2>&1
			if [ $? -eq 1 ]; then
				echo "Notice: Updating existing privatekey since exported privatekey is different..."
				KEY_COPY=1
			fi
		fi

		if [ $KEY_COPY -eq 1 ]; then
			echo "- Copying $KEY_EXPORTED to $KEY_EXISTING ..."
			cp $KEY_EXPORTED $KEY_EXISTING
			if [ $? -eq 0 ]; then
				echo "- Updating file ownership of $KEY_EXISTING ..."
				sudo chown $MQTT_CERT_OWNERSHIP $KEY_EXISTING
			fi
		fi

		CA_EXISTING=$MQTT_CERT_DIR/letsencrypt.pem
		CA_COPY=0
		if [ ! -f "$CA_EXISTING" ]; then
			# Copy the CA file to the MQTT certificate directory if it doesn't exist yet.
			echo "Notice: Copying CA file since doesn't exist yet..."
			CA_COPY=1
		else
			# Verify if the CA file needs to be copied to the MQTT certificate directory
			diff --binary --brief $CA_DOWNLOADED $CA_EXISTING > /dev/null 2>&1
			if [ $? -eq 1 ]; then
				echo "Notice: Updating existing CA file since downloaded CA file is different..."
				CA_COPY=1
			fi		
		fi

		if [ $CA_COPY -eq 1 ]; then
			echo "- Copying $CA_DOWNLOADED to $CA_EXISTING ..."
			cp $CA_DOWNLOADED $CA_EXISTING
			if [ $? -eq 0 ]; then
				echo "- Updating file ownership of $CA_EXISTING ..."
				sudo chown $MQTT_CERT_OWNERSHIP $CA_EXISTING
			fi
		fi

		# If we did something, then...
		if [[ $CERT_COPY -eq 1 || $KEY_COPY -eq 1 ]]; then
			# Check if container is running (to determine automatic restart)
			if [[ $(docker inspect --format '{{.State.Running}}' $MQTT_DOCKER_CONTAINER) == "true" ]]; then
				echo "Sending RESTART to $MQTT_DOCKER_CONTAINER ..."
				RET=$(docker container restart $MQTT_DOCKER_CONTAINER)

				# Note: sending a SIGHUP would be better, but this causes the logfile to show: "Reloading config." followed by "Error: Unable to open config file /mosquitto/config/mosquitto.conf." in my eclipse-docker container.
				#echo "- Sending SIGHUP to $MQTT_DOCKER_CONTAINER ..."
				#RET=$(docker kill --signal=HUP $MQTT_DOCKER_CONTAINER)
			fi
		fi
	fi

	# Remove the exported certificate directory
	[ -d $CERT_DUMP_DIR ] && rm -rf $CERT_DUMP_DIR
fi

exit $ERROR

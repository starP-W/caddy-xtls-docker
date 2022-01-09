#!/bin/bash
Precheck() {
	DOCKER_V=$(docker -v | grep -i "version")
	DOCKER_COMPOSE_V=$(docker-compose -v | grep -i "version")
	if [ -z "$DOCKER_V" ] || [ -z "$DOCKER_COMPOSE_V" ]; then
		echo "Docker or docker-compose not found. "
		exit 0
	fi
	EssentialFiles="tls Webdata Caddyfile .settings config.json docker-compose.yml"
	for file in $EssentialFiles; do
		if [ ! -e $file ]; then
			case "${file}" in
			"Caddyfile" | "config.json" | "docker-compose.yml")
				curl -sO "https://raw.githubusercontent.com/starP-W/caddy-xtls-docker/main/${file}"
				;;
			"tls" | "Webdata")
				mkdir $file
				;;
			".settings")
				touch $file
				;;
			*) ;;
			esac
		fi
	done

}

ChangeSettings() {
	if [ -z $(grep "$1" ./.settings) ]; then
		echo "$1=$2" >>./.settings
	else
		sed -i -E "s|$1=.+|$1=$2|g" ./.settings
	fi
}

SetCF() {
	read -p "Please Input Your CloudFlare Mailbox: " MAILBOX
	read -p "Please Input Your CloudFlare API_Key: " APIKEY
	sed -i -E "s|CF_Email=.+|CF_Email=$MAILBOX|g" ./docker-compose.yml
	sed -i -E "s|CF_Key=.+|CF_Key=$APIKEY|g" ./docker-compose.yml
	ChangeSettings "CF_Email" "$MAILBOX"
	ChangeSettings "CF_Key" "$APIKEY"
}

SetCaddy() {
	read -p "Please Input Your Domain: " FQDN
	sed -i -E "1s|http://[0-9a-zA-Z\-\.]+ \{|http://$FQDN \{|g" ./Caddyfile
	sed -i -E "2s|https://.*\{uri\}|https://$FQDN\{uri\}|g" ./Caddyfile
	sed -i -E "4s|http://[0-9a-zA-Z\-\.]+:8080 \{|http://$FQDN:8080 \{|g" ./Caddyfile
	read -p "Use 1.file_server or 2.reverse_proxy? (Default 1) : " mode
	case "${mode}" in
	2)
		echo "Using reverse_proxy mode"
		read -p "Please Input Your Proxy URL: " ppppp
		sed -i -E "5,+3s|^#+||g" ./Caddyfile
		sed -i -E "9,+1s|^|#|g" ./Caddyfile
		sed -i -E "5s|reverse_proxy \* .*|reverse_proxy \* $ppppp {|g" ./Caddyfile
		;;
	*)
		echo "Using file_server mode"
		sed -i -E "5,+3s|^|#|g" ./Caddyfile
		sed -i -E "9,+1s|^#+||g" ./Caddyfile
		;;
	esac
	ChangeSettings "FQDN" "$FQDN"
}

ChangeCF() {
	iscfset=$(grep 'CF_' ./.settings | awk '{print NR}' | sed -n '$p')
	case "${iscfset}" in
	2)
		read -p "Want to change CloudFlare settings? (yN default N): " changecf
		case "${changecf}" in
		'y' | 'Y')
			SetCF
			;;
		*) ;;
		esac
		;;
	*)
		SetCF
		;;
	esac
}

ChangeCaddy() {
	iscaddyset=$(grep 'FQDN' ./.settings | awk '{print NR}' | sed -n '$p')
	case "${iscaddyset}" in
	1)
		read -p "Want to change domain settings? (yN default N): " changefqdn
		case "${changefqdn}" in
		'y' | 'Y')
			SetCaddy
			;;
		*) ;;
		esac
		;;
	*)
		SetCaddy
		;;
	esac
}

ChangeUUID() {
	case "$(grep 'UUID' ./.settings | awk '{print NR}' | sed -n '$p')" in
	1)
		read -p "Change the UUID? (y or N def N)" setUUID
		case "${setUUID}" in
		'y' | 'Y')
			UUIDN1=$(curl -s https://www.uuidgenerator.net/api/version4)
			sed -i -E "s|\w{8}(-\w{4}){3}-\w{12}\",//xtls|$UUIDN1\",//xtls|g" ./config.json
			ChangeSettings "UUID" "$UUIDN1"
			;;
		*) ;;
		esac
		;;
	*)
		UUIDN1=$(curl -s https://www.uuidgenerator.net/api/version4)
		sed -i -E "s|\w{8}(-\w{4}){3}-\w{12}\",//xtls|$UUIDN1\",//xtls|g" ./config.json
		ChangeSettings "UUID" "$UUIDN1"

		;;
	esac
}

ChangeFlow() {
	CurrentFlowTpe=$(grep FLOW .settings | awk -F= '{print $2}')
	if [ -z "$CurrentFlowTpe" ]; then
		CurrentFlowTpe=$(grep 'flow' config.json | awk -F'"' '{print $4}')
	fi
	read -p "Current flow control is $CurrentFlowTpe, want to change it?(y or N def N)" ChangeFlowType
	case "${ChangeFlowType}" in
	'y' | 'Y')
		echo -e "Select the new flow control method(def 2):\n1.xtls-rprx-origin\n2.xtls-rprx-direct\n3.xtls-rprx-splice(Linux only)"
		read FlowType
		case "${FlowType}" in
		1)
			sed -i "s|$CurrentFlowTpe|xtls-rprx-origin|g" config.json
			ChangeSettings "FLOW" "xtls-rprx-origin"
			;;
		3)
			sed -i "s|$CurrentFlowTpe|xtls-rprx-splice|g" config.json
			ChangeSettings "FLOW" "xtls-rprx-splice"
			;;
		*)
			sed -i "s|$CurrentFlowTpe|xtls-rprx-direct|g" config.json
			ChangeSettings "FLOW" "xtls-rprx-direct"
			;;
		esac
		;;
	esac

}

ShowLink() {
	FQDN=$(grep 'FQDN' .settings | awk -F= '{print $2}')
	UUID=$(grep 'UUID' .settings | awk -F= '{print $2}')
	FLOW=$(grep 'FLOW' .settings | awk -F= '{print $2}')
	sharelink="vless://$UUID@$FQDN:443?flow=$FLOW&encryption=none&security=xtls&type=tcp&headerType=none#$FQDN"
	echo "Your VLESS ShareLink is:"
	echo $sharelink
}

Update() {
	imageID=$(docker-compose images | grep $1 | awk '{print $4}')
	if [ -z $imageID ]; then
		echo "no running container found"
		exit 0
	fi
	case "${1}" in
	"caddy" | "xray")
		#docker-compose stop $1
		docker-compose rm -s $1
		docker rmi $imageID
		docker-compose up -d $1
		;;
	"acme")
		echo "Emmmm"
		;;
	*)
		echo "default (none of caddy, xray or acme)"
		;;
	esac
}

Install() {
	Precheck
	ChangeCF
	ChangeCaddy
	ChangeUUID
	ChangeFlow
	docker-compose down --rmi all
	docker-compose up -d
	docker exec acme --issue --dns dns_cf -d $FQDN --server letsencrypt
	docker exec acme --install-cert -d $FQDN --key-file /tls/key.key --fullchain-file /tls/cert.crt
	docker-compose restart
	ShowLink
}

Remove() {
	docker-compose down --rmi all
}

#echo "Your Random XTLS UUID Is: $UUIDN1"
main() {
	case "${1}" in
	"install")
		Install
		;;
	"update")
		Update $2
		;;
	"remove")
		Remove
		;;
	*)
		echo "Usage 1.install 2.update xray/caddy 3.remove
example bash install.sh install"
		;;
	esac

}

main $1 $2

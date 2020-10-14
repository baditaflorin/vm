#!/bin/bash

# T&M Hansson IT AB © - 2020, https://www.hanssonit.se/
# Copyright © 2020 Simon Lindner (https://github.com/szaimen)

# shellcheck disable=2034,2059,1091
true
SCRIPT_NAME="Geoblock"
SCRIPT_EXPLAINER="This script let's you allow access to your websites only from chosen countries."
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/nextcloud/vm/master/lib.sh)

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Must be root
root_check

# Show explainer
msg_box "$SCRIPT_EXPLAINER"

# Check if it is already configured
if ! grep -q "^#Geoip-block" /etc/apache2/apache2.conf
then
    # Ask for installing
    install_popup "$SCRIPT_NAME"
else
    # Ask for removal or reinstallation
    reinstall_remove_menu "$SCRIPT_NAME"
    # Removal
    if is_this_installed jq
    then
        apt purge jq -y
    fi
    if is_this_installed libapache2-mod-geoip
    then
        a2dismod geoip
        apt purge libapache2-mod-geoip -y
    fi
    apt autoremove -y
    sed -i "/^#Geoip-block-start/,/^#Geoip-block-end/d" /etc/apache2/apache2.conf
    check_command systemctl restart apache2
    # Show successful uninstall if applicable
    removal_popup "$SCRIPT_NAME"
fi

# Install needed tools
# Unfortunately jq is needed for this
install_if_not jq
install_if_not libapache2-mod-geoip

# Enable apache mod
check_command a2enmod geoip rewrite
check_command systemctl restart apache2

# Download newest dat files
# get_newest_dat_files # TODO: Uncomment this in a followup PR to be able to test this properly

# Restrict to countries and/or continents
choice=$(whiptail --title "$TITLE"  --checklist \
"Do you want to restrict to countries and/or continents?
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Countries" "" ON \
"Continents" "" ON 3>&1 1>&2 2>&3)
if [ -z "$choice" ]
then
    exit 1
fi

# Countries
if [[ "$choice" = *"Countries"* ]]
then
    # Get country names
    COUNTRY_NAMES=$(jq .[][].name /usr/share/iso-codes/json/iso_3166-1.json | sed 's|^"||;s|"$||')
    mapfile -t COUNTRY_NAMES <<< "$COUNTRY_NAMES"

    # Get country codes
    COUNTRY_CODES=$(jq .[][].alpha_2 /usr/share/iso-codes/json/iso_3166-1.json | sed 's|^"||;s|"$||')
    mapfile -t COUNTRY_CODES <<< "$COUNTRY_CODES"

    # Check if both arrays match
    if [ "${#COUNTRY_NAMES[@]}" != "${#COUNTRY_CODES[@]}" ]
    then
        msg_box "Somethings is wrong. The names length is not equal to the codees length.
    Please report this to $ISSUES"
    fi

    # Create checklist
    args=(whiptail --title "$TITLE - $SUBTITLE" --separate-output --checklist \
"Please select all countries that shall have access to your websites.
All countries that are not selected will not have access to your websites \
if you not choose to activate their continent.
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4)
    count=0
    while [ "$count" -lt "${#COUNTRY_NAMES[@]}" ]
    do
        args+=("${COUNTRY_CODES[$count]}" "${COUNTRY_NAMES[$count]}" OFF)
        ((count++))
    done

    # Let the user choose the countries
    selected_options=$("${args[@]}" 3>&1 1>&2 2>&3)
    if [ -z "$selected_options" ]
    then
        unset selected_options
    fi
fi

# Continents
if [[ "$choice" = *"Continents"* ]]
then
    # Restrict to continents
    choice=$(whiptail --title "$TITLE" --separate-output --checklist \
"Please choose all continents that shall have access to your websites.
All countries on not selected continents will not have access to your websites \
if you haven't explicitely chosen them in the countries menu before.
$CHECKLIST_GUIDE\n\n$RUN_LATER_GUIDE" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"AF" "Africa" OFF \
"AN" "Antarctica" OFF \
"AS" "Asia" OFF \
"EU" "Europe" OFF \
"NA" "North America" OFF \
"OC" "Oceania" OFF \
"SA" "South America" OFF 3>&1 1>&2 2>&3)
    if [ -z "$choice" ]
    then
        unset choice
    fi
else
    unset choice
fi

# Exit if nothing chosen
if [ -z "$selected_options" ] && [ -z "$choice" ]
then
    exit 1
fi

# Convert to array
if [ -n "$selected_options" ]
then
    mapfile -t selected_options <<< "$selected_options"
fi
if [ -n "$choice" ]
then
    mapfile -t choice <<< "$choice"
fi

GEOIP_CONF="#Geoip-block-start - Please don't remove or change this line
<IfModule mod_geoip.c>
  GeoIPEnable On
  GeoIPDBFile /usr/share/GeoIP/GeoIP.dat
  GeoIPDBFile /usr/share/GeoIP/GeoIPv6.dat
</IfModule>
<Location />\n"
for continent in "${choice[@]}"
do
    GEOIP_CONF+="  SetEnvIf GEOIP_CONTINENT_CODE    $continent AllowCountryOrContinent\n"
    GEOIP_CONF+="  SetEnvIf GEOIP_CONTINENT_CODE_V6 $continent AllowCountryOrContinent\n"
done
for country in "${selected_options[@]}"
do
    GEOIP_CONF+="  SetEnvIf GEOIP_COUNTRY_CODE    $country AllowCountryOrContinent\n"
    GEOIP_CONF+="  SetEnvIf GEOIP_COUNTRY_CODE_V6 $country AllowCountryOrContinent\n"
done
GEOIP_CONF+="  Allow from env=AllowCountryOrContinent
  Allow from 127.0.0.1/8
  Allow from 192.168.0.0/16
  Allow from 172.16.0.0/12
  Allow from 10.0.0.0/8
  Order Deny,Allow
  Deny from all
</Location>
#Geoip-block-end - Please don't remove or change this line"

# Write everything to the file
echo -e "$GEOIP_CONF" >> /etc/apache2/apache2.conf

check_command systemctl restart apache2

msg_box "Geoblock was successfully configured"

exit

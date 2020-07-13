#!/usr/bin/env bash
################################################################################
# This is property of eXtremeSHOK.com
# You are free to use, modify and distribute, however you may not remove this notice.
# Copyright (c) Adrian Jon Kriel :: admin@extremeshok.com
################################################################################
#
# Notes:
# Script must be placed into the same directory as the docker-compose.yml
#
# Assumptions: Docker and Docker-compose Installed
#
# Tested on KVM, VirtualBox and Dedicated Server
#
#
################################################################################
#
#    THERE ARE NO USER CONFIGURABLE OPTIONS IN THIS SCRIPT
#
################################################################################

################# VARIBLES
PWD="/datastore"
VOLUMES="${PWD}/volumes"
VHOST_DIR="${VOLUMES}/www-vhosts"
OLS_HTTPD_CONF="${VOLUMES}/www-conf/conf/httpd_config.conf"
ACME_DOMAIN_LIST="${VOLUMES}/acme/domain_list.txt"
TIMESTAMP_SQL_BACKUP='no'
CONTAINER_OLS='openlitespeed'
CONTAINER_MYSQL='mysql'
EPACE='   '

################# GLOBALS
DOMAIN=""
DOMAIN_ESCAPED=""
FILTERED_DOMAIN=""

################# SUPPORTING FUNCTIONS :: START

function fst_match_line () {
  FIRST_LINE_NUM=$(grep -n -m 1 ${1} ${2} | awk -F ':' '{print $1}')
}

function fst_match_after () {
  FIRST_NUM_AFTER=$(tail -n +${1} ${2} | grep -n -m 1 ${3} | awk -F ':' '{print $1}')
}

function lst_match_line () {
  fst_match_after ${1} ${2} ${3}
  LAST_LINE_NUM=$((${FIRST_LINE_NUM}+${FIRST_NUM_AFTER}-1))
}

# function to check if the $2 value is not null and does not start with -
function xshok_check_s2 () {
  if [ "$1" ]; then
    if [[ "$1" =~ ^-.* ]]; then
      echo "ERROR: Missing value for option or value begins with -" "="
      exit 1
    fi
  else
    echo "ERROR: Missing value for option" "="
    exit 1
  fi
}

function xshok_validate_domain () { #domain
  DOMAIN="${1}"
  DOMAIN="${DOMAIN,,}"
  DOMAIN="${DOMAIN#www.*}" # remove www.
  DOMAIN_ESCAPED=${DOMAIN/\./\\.}
  FILTERED_DOMAIN=${DOMAIN//\./_}
  if [[ $DOMAIN = .* ]] ; then
    echo "ERROR: do not start domain with ."
    exit 1
  fi
  if [[ $DOMAIN = *. ]] ; then
    echo "ERROR: do not end domain with ."
    exit 1
  fi
  if [ "$DOMAIN" == "" ] ; then
    echo "ERROR: empty domain, please add the domain name after the command option"
    exit 1
  fi
  if [ "${DOMAIN%%.*}" == "" ] || [ "${DOMAIN##*.}" == "" ] || [ "${DOMAIN##*.}" == "${DOMAIN%%.*}" ] ; then
    echo "ERROR: invalid domain: ${DOMAIN}"
    exit 1
  fi
  VALID_DOMAIN=$( echo "$DOMAIN" | grep -P "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$" )
  if [ "$VALID_DOMAIN" != "$DOMAIN" ] || [ "$DOMAIN" == "" ] ; then
    echo "ERROR: invalid domain: ${DOMAIN}"
    exit 1
  fi
  echo "DOMAIN: ${DOMAIN}"
}

function xshok_container_is_running (){ #container_name
  CONTAINER_NAME="${1}"
  if [ -z $CONTAINER_NAME ] ; then
    echo "ERROR: xshok_container_is_running container_name not specificed"
    exit 1
  fi
  if [ -z $(docker-compose ps -q "$CONTAINER_NAME") ] || [ -z $(docker ps -q --no-trunc | grep $(docker-compose ps -q "$CONTAINER_NAME")) ]; then
    echo "ERROR: Docker Container: ${CONTAINER_NAME}, it's not running."
    exit 1
  fi
}

################# SUPPORTING FUNCTIONS  :: END


################# WEBSITE FUNCTIONS  :: START

################# list all websites
function xshok_website_list () {
  ## /var/www/vhosts
  if [ -d "${VHOST_DIR}" ] ; then
    echo "Website List"
    echo "==== vhost ============ home ============ domains ===="
    while IFS= read -r -d '' vhost_dir; do
      vhost="${vhost_dir##*/}"
      short_vhost_dir="${vhost_dir/$VOLUMES\//}"
      echo "${vhost} = ${short_vhost_dir} = $(grep "vhDomain.*${vhost}" "${OLS_HTTPD_CONF}" | sed -e  's/vhDomain//g' | xargs)"
    done < <(find "${VHOST_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)  #dirs
    echo ""
  fi
}

################# add a website
function xshok_website_add () { #domain
  xshok_validate_domain "${1}"
  if [ "$(grep -E "member.*${DOMAIN_ESCAPED}" ${OLS_HTTPD_CONF})" != '' ]; then
    echo "Warning: ${DOMAIN} already exists, Check ${OLS_HTTPD_CONF}"
  else
    echo "Adding ${DOMAIN},www.${DOMAIN} "
    perl -0777 -p -i -e 's/(vhTemplate vhost \{[^}]+)\}*(^.*listeners.*$)/\1$2
        member '${DOMAIN}' {
          vhDomain              '${DOMAIN},www.${DOMAIN}'
    }/gmi' ${OLS_HTTPD_CONF}
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/cron" ]; then
    echo "Creating Directory: ${VHOST_DIR}/${DOMAIN}/cron"
    mkdir -p "${VHOST_DIR}/${DOMAIN}/cron"
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/certs" ]; then
    echo "Creating Directory: ${VHOST_DIR}/${DOMAIN}/certs"
    mkdir -p "${VHOST_DIR}/${DOMAIN}/certs"
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/dbinfo" ]; then
    echo "Creating Directory: ${VHOST_DIR}/${DOMAIN}/dbinfo"
    mkdir -p "${VHOST_DIR}/${DOMAIN}/dbinfo"
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/html" ]; then
    echo "Creating Directory: ${VHOST_DIR}/${DOMAIN}/html"
    mkdir -p "${VHOST_DIR}/${DOMAIN}/html"
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/logs" ]; then
    echo "Creating Directory: ${VHOST_DIR}/${DOMAIN}/logs"
    mkdir -p "${VHOST_DIR}/${DOMAIN}/logs"
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/sql" ]; then
    echo "Creating Directory: ${VHOST_DIR}/${DOMAIN}/sql"
    mkdir -p "${VHOST_DIR}/${DOMAIN}/sql"
  fi
  chmod 777 ${VHOST_DIR}/${DOMAIN}
  chmod 777 ${VHOST_DIR}/${DOMAIN}/*
}

################# delete an existing website
function xshok_website_delete () { #domain
  xshok_validate_domain "${1}"
  if [ "$(grep -E "member.*${DOMAIN_ESCAPED}" ${OLS_HTTPD_CONF})" == '' ]; then
    echo "ERROR: ${DOMAIN} does NOT exist, Check ${OLS_HTTPD_CONF}"
    exit 1
  fi
  echo "Removing ${DOMAIN},www.${DOMAIN} "
  fst_match_line ${1} ${OLS_HTTPD_CONF}
  lst_match_line ${FIRST_LINE_NUM} ${OLS_HTTPD_CONF} '}'
  sed -i "${FIRST_LINE_NUM},${LAST_LINE_NUM}d" ${OLS_HTTPD_CONF}
  echo "Remeber to remove the dir:  ${VHOST_DIR}/${DOMAIN}/"
  xshok_restart
}

################# fix permission and ownership of an existing website
function xshok_website_permissions () { #domain
  xshok_validate_domain "${1}"
  if [ "$(grep -E "member.*${DOMAIN_ESCAPED}" ${OLS_HTTPD_CONF})" == '' ]; then
    echo "Error: ${DOMAIN} does not exist"
    exit 1
  fi
  if [ ! -d "${VHOST_DIR}/${DOMAIN}/html" ]; then
    echo "Error: ${VHOST_DIR}/${DOMAIN}/html does not exist"
    exit 1
  fi
  echo "Setting permissions"
  find "${VHOST_DIR}/${DOMAIN}/html" -type f -exec chmod 0664 {} \;
  find "${VHOST_DIR}/${DOMAIN}/html" -type d -exec chmod 0775 {} \;
  echo "Setting Ownership"
  chown -R nobody:nogroup "${VHOST_DIR}/${DOMAIN}/html"
}

################# WEBSITE FUNCTIONS  :: END

################# DATABASE FUNCTIONS  :: START

################## list all databases for domain
function xshok_database_list () { #domain
  xshok_container_is_running "$CONTAINER_MYSQL"
  xshok_validate_domain "${1}"

  result="$(docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe \"SHOW DATABASES LIKE '%%${FILTERED_DOMAIN}%%'\"")"
  if [ "$result" != "" ] ; then
    echo "Databases list for ${DOMAIN}: "
    echo "$result"
  else
    echo "No Databases found for ${DOMAIN}"
  fi
}

################## add database to domain
function xshok_database_add () { #domain
  xshok_container_is_running "$CONTAINER_MYSQL"
  xshok_validate_domain "${1}"

  DBNAME="${FILTERED_DOMAIN}-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)"
  DBUSER="$DBNAME"
  DBPASS="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

  if [ -f "${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}" ] ; then
    echo "Database Info File Found"
  fi

  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e 'status'" >/dev/null 2>&1
  if [ ${?} != 0 ]; then
    echo 'ERROR: DB access failed, please check!'
  fi

  if docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -s -N -e \"SELECT IF(EXISTS (SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DBNAME}'), 'yes','no')\"" | grep -q "yes" ; then
    echo "ERROR: Database exists"
    exit 1
  else
    echo "DATABASE: ${DBNAME}"
  fi

  echo "Start Transaction"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'START TRANSACTION'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: failed starting transaction, please check!'
    exit 1
  fi
  echo "- Create DB"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'CREATE DATABASE IF NOT EXISTS \`${DBNAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: create DB, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "- Create user"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'CREATE USER IF NOT EXISTS \`${DBUSER}\`@\`%\`'"
  if [ ${?} != 0 ]; then
    echo 'ERROR:create user failed, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "- Set user password"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe \"ALTER USER '${DBUSER}'@'%' IDENTIFIED BY '${DBPASS}'\""
  if [ ${?} != 0 ]; then
    echo 'ERROR: set user password failed, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "- Assign permissions"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'GRANT ALL PRIVILEGES ON \`${DBNAME}\`.* TO \`${DBUSER}\`@\`%\`'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: assign permissions failed, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "Commit transaction"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'COMMIT'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: failed starting transaction, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "Flush (apply) privileges"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'FLUSH PRIVILEGES'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: flush failed, please check!'
    exit 1
  fi
  echo "Saving dbinfo to ${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}"
  mkdir -p "${VHOST_DIR}/${DOMAIN}/dbinfo"
  cat << EOF > "${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}"
  DB NAME: ${DBNAME}
  DB USER: ${DBUSER}
  DB PASS: ${DBPASS}
EOF
  echo "DB NAME: ${DBNAME}"
  echo "DB USER: ${DBUSER}"
  echo "DB PASS: ${DBPASS}"
}

################## delete database and database user
function xshok_database_delete () { #database
  DBNAME="${1}"
  #get valid domain from database name
  FILTERED_DOMAIN=${DBNAME%-*}
  DOMAIN="${FILTERED_DOMAIN//_/.}"
  xshok_container_is_running "$CONTAINER_MYSQL"
  xshok_validate_domain "${DOMAIN}"

  if [ -f "${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}" ] ; then
    echo "Database Info File Found"
  fi

  if docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -s -N -e \"SELECT IF(EXISTS (SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DBNAME}'), 'yes','no')\"" | grep -q "yes" ; then
    echo "DATABASE: ${DBNAME}"
  else
    echo "ERROR: Database does not exist"
    exit 1
  fi

  echo "Start Transaction"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'START TRANSACTION'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: failed starting transaction, please check!'
    exit 1
  fi
  echo "- Drop the database"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'DROP DATABASE IF EXISTS \`${DBNAME}\`'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: assign permissions failed, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "- Delete the user"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe \"DELETE FROM mysql.global_priv WHERE User = '${DBNAME}'\""
  if [ ${?} != 0 ]; then
    echo 'ERROR: assign permissions failed, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "Commit transaction"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'COMMIT'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: failed starting transaction, please check!'
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'ROLLBACK'"
    exit 1
  fi
  echo "Flush (apply) privileges"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe 'FLUSH PRIVILEGES'"
  if [ ${?} != 0 ]; then
    echo 'ERROR: flush failed, please check!'
    exit 1
  fi
  echo "Remove dbinfo for ${DBNAME}"
  rm -f "${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}"

}

################## reset password for database
function xshok_database_password () { #database
  DBNAME="${1}"
  #get valid domain from database name
  FILTERED_DOMAIN=${DBNAME%-*}
  DOMAIN="${FILTERED_DOMAIN//_/.}"
  xshok_container_is_running "$CONTAINER_MYSQL"
  xshok_validate_domain "${DOMAIN}"

  if [ -f "${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}" ] ; then
    echo "Database Info File Found"
  fi

  if docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -s -N -e \"SELECT IF(EXISTS (SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DBNAME}'), 'yes','no')\"" | grep -q "yes" ; then
    echo "DATABASE: ${DBNAME}"
  else
    echo "ERROR: Database does not exist"
    exit 1
  fi

  DBUSER="$DBNAME"
  DBPASS="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
  docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe \"ALTER USER '${DBUSER}'@'%' IDENTIFIED BY '${DBPASS}'\""
  if [ ${?} != 0 ]; then
    echo 'ERROR: password set failed, please check!'
    exit 1
  fi
  echo "Saving sql to ${VHOST_DIR}/${DOMAIN}/sql/${DBNAME}"
  mkdir -p "${VHOST_DIR}/${DOMAIN}/dbinfo"
  cat << EOF > "${VHOST_DIR}/${DOMAIN}/dbinfo/${DBNAME}"
  DB NAME: ${DBNAME}
  DB USER: ${DBUSER}
  DB PASS: ${DBPASS}
EOF
  echo "DB NAME: ${DBNAME}"
  echo "DB USER: ${DBUSER}"
  echo "DB PASS: ${DBPASS}"
}

################## backup database
function xshok_backup_database () { #database #filename*optional
  DBNAME="${1}"
  DBFILENAME="${2}"
  #get valid domain from database name
  FILTERED_DOMAIN=${DBNAME%-*}
  DOMAIN="${FILTERED_DOMAIN//_/.}"
  xshok_container_is_running "$CONTAINER_MYSQL"
  xshok_validate_domain "${DOMAIN}"

  if [ "$TIMESTAMP_SQL_BACKUP" == "yes" ] ; then
    echo "Using a timestamp for the backup name"
    TIMESTAMP="-$(date +%Y-%m-%d-%H-%M-%S)"
  else
    TIMESTAMP=""
  fi

  if [ "$DBFILENAME" == "" ] ; then
    DBFILENAME="${VHOST_DIR}/${DOMAIN}/sql/${DBNAME}${TIMESTAMP}.sql.gz"
  fi

  if docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -s -N -e \"SELECT IF(EXISTS (SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DBNAME}'), 'yes','no')\"" | grep -q "yes" ; then
    echo "DATABASE: ${DBNAME}"
  else
    echo "ERROR: Database does not exist"
    exit 1
  fi

  mkdir -p "${VHOST_DIR}/${DOMAIN}/sql"

  if [ -f "${DBFILENAME}" ] ; then
    echo "Previous Backup Found, overwriting"
  fi

  if [ ${DBFILENAME##*.} == "gz" ] ; then
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysqldump -uroot -p'${MYSQL_ROOT_PASSWORD}' --net_buffer_length 4096 --no-create-info --single-transaction \"${DBNAME}\"" | gzip -9 > "${DBFILENAME}"
    if [ ${?} != 0 ]; then
      echo 'ERROR: backup failed, please check!'
      exit 1
    fi
  else
    docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysqldump -uroot -p'${MYSQL_ROOT_PASSWORD}' --net_buffer_length 4096 --no-create-info --single-transaction \"${DBNAME}\"" > "${DBFILENAME}"
    if [ ${?} != 0 ]; then
      echo 'ERROR: backup failed, please check!'
      exit 1
    fi
  fi
  echo "Backup saved to : ${DBFILENAME}"
}

################## backup all database
function xshok_backup_all_database () { #path*optional
  DBPATH="${1}"
  xshok_container_is_running "$CONTAINER_MYSQL"

  database_list="$(docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -qfNsBe \"SHOW DATABASES\"" | xargs)"

  for DBNAME in $database_list; do
  #while IFS= read -r -d " " DBNAME; do
    if [ "$DBNAME" != "" ] && [ "$DBNAME" != "information_schema" ] && [ "$DBNAME" != "information_schema" ] && [ "$DBNAME" != "performance_schema" ] && [ "$DBNAME" != "mysql" ] ; then
      echo ":------${DBNAME}-----:"
      if [ -z "$DBPATH" ] ; then
        result="$(xshok_backup_database "$DBNAME")"
      else
        result="$(xshok_backup_database "$DBNAME" "${DBPATH}/${DBNAME}.sql.gz")"
      fi
      echo $result
    fi
  done
}

################## restore database
function xshok_database_restore () { #database #filename
  DBNAME="${1}"
  DBFILENAME="${2}"
  #get valid domain from database name
  FILTERED_DOMAIN=${DBNAME%-*}
  DOMAIN="${FILTERED_DOMAIN//_/.}"
  xshok_container_is_running "$CONTAINER_MYSQL"
  xshok_validate_domain "${DOMAIN}"

  if [ "$DBFILENAME" == "" ] ; then
    echo "ERROR: empty filename, please add the domain name after the domain"
    exit 1
  fi
  if [ -f "${DBFILENAME}" ] ; then
    echo "FILE: ${DBFILENAME}"
  elif [ -f "${VHOST_DIR}/${DOMAIN}/${DBFILENAME}" ] ; then
    echo "FILE: ${VHOST_DIR}/${DOMAIN}/${DBFILENAME}"
    DBFILENAME="${VHOST_DIR}/${DOMAIN}/${DBFILENAME}"
  elif [ -f "${VHOST_DIR}/${DOMAIN}/sql/${DBFILENAME}" ] ; then
    echo "FILE: ${VHOST_DIR}/${DOMAIN}/sql/${DBFILENAME}"
    DBFILENAME="${VHOST_DIR}/${DOMAIN}/sql/${DBFILENAME}"
  else
    echo "ERROR: file not found ${DBFILENAME}"
    exit 1
  fi

  if docker-compose exec -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' -s -N -e \"SELECT IF(EXISTS (SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DBNAME}'), 'yes','no')\"" | grep -q "yes" ; then
    echo "DATABASE: ${DBNAME}"
  else
    echo "ERROR: Database does not exist"
    exit 1
  fi

  TEMPSQL="/tmp/xs-sql-xs-$(date +%s).sql"

  # create tempsql
  if [ ${DBFILENAME##*.} == "gz" ] ; then
    zcat "${DBFILENAME}" > "${TEMPSQL}"
  else
    cp -f "${DBFILENAME}" "${TEMPSQL}"
  fi

  # filter(remove) create database, alter database, drop database and use statments from restore sql file
  sed -i -e 's/^[[:blank:]]*CREATE DATABASE.*//Ig' "${TEMPSQL}"
  sed -i -e 's/^[[:blank:]]*ALTER DATABASE.*//Ig' "${TEMPSQL}"
  sed -i -e 's/^[[:blank:]]*DROP DATABASE.*//Ig' "${TEMPSQL}"
  sed -i -e 's/^[[:blank:]]*USE.*//Ig' "${TEMPSQL}"

  if [ -f "${TEMPSQL}" ] ; then
    cat "${TEMPSQL}" | docker-compose exec -T -T ${CONTAINER_MYSQL} su -c "mysql -uroot -p'${MYSQL_ROOT_PASSWORD}' \"${DBNAME}\""
    if [ ${?} != 0 ]; then
      echo 'ERROR: restore failed, please check!'
      exit 1
    fi
  else
    echo "ERROR: TEMPSQL does not exist: ${TEMPSQL}"
    exit 1
  fi

  # remove tempsql
  rm -f "${TEMPSQL}"

  echo "Restored ${DBFILENAME} to  ${DBNAME} for ${DOMAIN}"
}

################# DATABASE FUNCTIONS  :: END

################# SSL FUNCTIONS  :: START

function xshok_ssl_list () {
  echo "SSL List"
  echo "---- vhost -------- subdomains ----"
  cat "${ACME_DOMAIN_LIST}"

}
function xshok_ssl_add () { #domain
  xshok_validate_domain "${1}"
  if grep -q "^${DOMAIN}" "${ACME_DOMAIN_LIST}" ; then
    echo "Warning: SSL already exists for ${DOMAIN} www.${DOMAIN}, Check ${ACME_DOMAIN_LIST}"
  else
    echo "Adding SSL for ${DOMAIN} www.${DOMAIN} "
    echo "${DOMAIN} www.${DOMAIN}" >> "${ACME_DOMAIN_LIST}"
  fi
}

function xshok_ssl_delete () {
  xshok_validate_domain "${1}"
  if ! grep -q "^${DOMAIN}" "${ACME_DOMAIN_LIST}" ; then
    echo "ERROR: SSL for ${DOMAIN} does NOT exist, Check ${ACME_DOMAIN_LIST}"
    exit 1
  fi
  echo "Removing SSL ${DOMAIN} www.${DOMAIN} "
  sed -i "/${DOMAIN} .*/d" /datastore/volumes/acme/domain_list.txt
  echo "Remeber to remove the dir:  ${VHOST_DIR}/${DOMAIN}/certs"
}

################# SSL FUNCTIONS  :: END

################# ADVANCED FUNCTIONS  :: START

function xshok_website_warm_cache () { #domain
  xshok_container_is_running "$CONTAINER_OLS"
  xshok_validate_domain "${1}"
  wget --quiet "https://${DOMAIN}/sitemap.xml" --no-cache --output-document - | egrep -o "http(s?):\/\/${DOMAIN[^]} \"\(\)\]*" | while read line; do
    time curl -A 'Cache Warmer' -s -L $line > /dev/null 2>&1
    echo $line
  done
}

function xshok_docker_mysql_optimiser () {
  xshok_container_is_running "$CONTAINER_MYSQL"
  ## works, but needs refactoring .. ie own docker image
  docker-compose exec -T ${CONTAINER_MYSQL} /bin/bash -c 'apt-get update && apt-get install -y wget perl && wget http://mysqltuner.pl/ -O /tmp/mysqltuner.pl && perl /tmp/mysqltuner.pl --host 127.0.0.1 --user root --pass ${MYSQL_ROOT_PASSWORD}'
  #docker-compose exec -T mysql /bin/bash -c '/usr/bin/mysqlcheck --host 127.0.0.1 --user root --password=${MYSQL_ROOT_PASSWORD} --all-databases --optimize --skip-write-binlog'
}

################# ADVANCED FUNCTIONS  :: END


################# GENERAL FUNCTIONS  :: START

################# docker start
function xshok_docker_up () {

  #Automatically create required volume dirs
  ## remove all comments
  TEMP_COMPOSE="/tmp/xs_$(date +"%s")"
  sed -e '1{/^#!/ {p}}; /^[\t\ ]*#/d;/\.*#.*/ {/[\x22\x27].*#.*[\x22\x27]/ !{:regular_loop s/\(.*\)*[^\]#.*/\1/;t regular_loop}; /[\x22\x27].*#.*[\x22\x27]/ {:special_loop s/\([\x22\x27].*#.*[^\x22\x27]\)#.*/\1/;t special_loop}; /\\#/ {:second_special_loop s/\(.*\\#.*[^\]\)#.*/\1/;t second_special_loop}}' "${PWD}/docker-compose.yml" > "$TEMP_COMPOSE"
  mkdir -p "${PWD}/volumes/"
  VOLUMEDIR_ARRAY=$(grep "device:.*\${PWD}/volumes/" "$TEMP_COMPOSE")
  for VOLUMEDIR in $VOLUMEDIR_ARRAY ; do
    if [[ $VOLUMEDIR =~ "\${PWD}" ]]; then
      VOLUMEDIR="${VOLUMEDIR/\$\{PWD\}\//}"
      if [ ! -d "$VOLUMEDIR" ] ; then
        if [ ! -f "$VOLUMEDIR" ] && [[ $VOLUMEDIR != *.* ]] ; then
          echo "Creating dir: $VOLUMEDIR"
          mkdir -p "$VOLUMEDIR"
          chmod 777 "$VOLUMEDIR"
        elif [ ! -d "$VOLUMEDIR" ] && [[ $VOLUMEDIR == *.* ]] ; then
          echo "Creating file: $VOLUMEDIR"
          touch -p "$VOLUMEDIR"
        fi
      fi
    fi
  done
  rm -f "$TEMP_COMPOSE"

  docker-compose down --remove-orphans
  # detect if there are any running containers and manually stop and remove them
  if docker ps -q 2> /dev/null ; then
    docker stop $(docker ps -q)
    sleep 1
    docker rm $(docker ps -q)
  fi

  docker-compose pull --include-deps
  docker-compose up -d --force-recreate --build

}

################# docker stop
function xshok_docker_down () {
  docker-compose down
  sync
  docker stop $(docker ps -q)
  sync
}

################## restart webserver
function xshok_restart () {
  xshok_container_is_running "$CONTAINER_OLS"
  echo "Gracefully restarting web server with zero down time"
  docker-compose exec -T ${CONTAINER_OLS} su -c '/usr/local/lsws/bin/lswsctrl restart >/dev/null'
}

################## generate new password for web admin
function xshok_password () {
  xshok_container_is_running "$CONTAINER_OLS"
  ADMINPASS="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

  docker-compose exec -T ${CONTAINER_OLS} su -c 'echo "admin:$(/usr/local/lsws/admin/fcgi-bin/admin_php* -q /usr/local/lsws/admin/misc/htpasswd.php '${ADMINPASS}')" > /usr/local/lsws/admin/conf/htpasswd';
  if [ ${?} != 0 ]; then
    echo 'ERROR: password set failed, please check!'
    exit 1
  fi
  echo "WEBADMIN: https://$(hostname -f):7080"
  echo "WEBADMIN USER: admin"
  echo "WEBADMIN PASS: ${ADMINPASS}"
}

################# docker boot
function xshok_docker_boot () {

  if [ ! -d "/etc/systemd/system/" ] ; then
    echo "ERROR: systemd not detected"
    exit 1
  fi
  if [ ! -f "${PWD}/xshok-admin.sh" ] ; then
    echo "ERROR: ${PWD}/xshok-admin.sh not detected"
    exit 1
  fi

  echo "Generating Systemd service"
  cat << EOF > "/etc/systemd/system/xshok-webserver.service"
[Unit]
Description=eXtremeSHOK Webserver Service
Requires=docker.service
After=docker.service

[Install]
WantedBy=multi-user.target

[Service]
Type=oneshot
TimeoutStartSec=0
RemainAfterExit=yes
WorkingDirectory=${DIRNAME}
EOF

  echo "ExecStart=/bin/bash ${PWD}/xshok-admin.sh --start" >> "/etc/systemd/system/xshok-webserver.service"
  echo "ExecStop=/bin/bash ${PWD}/xshok-admin.sh --stop" >> "/etc/systemd/system/xshok-webserver.service"
  echo "ExecReload=/bin/bash ${PWD}/xshok-admin.sh --reload" >> "/etc/systemd/system/xshok-webserver.service"

  echo "Created: /etc/systemd/system/xshok-webserver.service"
  systemctl daemon-reload
  systemctl enable xshok-webserver

  echo "Available Systemd Commands:"
  echo "Start-> systemctl start xshok-webserver"
  echo "Stop-> systemctl stop xshok-webserver"
  echo "Reload-> systemctl reload xshok-webserver"

}

################## generate env
function xshok_env () {
  echo "Generating .env"
  if [ ! -f "${PWD}/default.env" ] ; then
    echo "missing ${PWD}/default.env"
    exit 1
  fi
  cp -f "${PWD}/default.env" "${PWD}/.env"
  cat << EOF >> "${PWD}/.env"
# ------------------------------
# SQL database configuration
# ------------------------------
MYSQL_DATABASE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
MYSQL_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
MYSQL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
# ------------------------------
EOF
  echo "Done"
}

################# GENERAL FUNCTIONS  :: END

if [ ! -f "${PWD}/.env" ] ; then
  echo "missing .env"
  xshok_env
fi

source "${PWD}/.env"

echo "eXtremeSHOK.com Docker Webserver"

help_message () {
  echo -e "\033[1mWEBSITE OPTIONS\033[0m"
  echo "${EPACE}-wl | --website-list"
  echo "${EPACE}${EPACE} list all websites"
  echo "${EPACE}-wa | --website-add [domain_name]"
  echo "${EPACE}${EPACE} add a website"
  echo "${EPACE}-wd | --website-delete [domain_name]"
  echo "${EPACE}${EPACE} delete a website"
  echo "${EPACE}-wp | --website-permissions [domain_name]"
  echo "${EPACE}${EPACE} fix permissions and ownership of a website"
  echo -e "\033[1mDATABASE OPTIONS\033[0m"
  echo "${EPACE}-dl | --database-list [domain_name]"
  echo "${EPACE}${EPACE} list all databases for domain"
  echo "${EPACE}-da | --database-add [domain_name]"
  echo "${EPACE}${EPACE} add a database to domain, database name, user and pass autogenerated"
  echo "${EPACE}-dd | --database-delete [database_name]"
  echo "${EPACE}${EPACE} delete a database"
  echo "${EPACE}-dp | --database-password [database_name]"
  echo "${EPACE}${EPACE} reset the password for a database"
  echo "${EPACE}-dr | --database-restore [database_name] [/your/path/file_name]"
  echo "${EPACE}${EPACE} restore a database backup file to database_name, supports .gz and .sql"
  echo -e "\033[1mBACKUP OPTIONS\033[0m"
  echo "${EPACE}-ba | --backup-all [/your/path]*optional*"
  echo "${EPACE}${EPACE} backup all databases, optional backup path, file will use the default sql/databasename.sql.gz"
  echo "${EPACE}-bd | --backup-database [database_name] [/your/path/file_name]*optional*"
  echo "${EPACE}${EPACE} backup a database, optional backup filename, will use the default sql/databasename.sql.gz if not specified"
  echo -e "\033[1mSSL OPTIONS\033[0m"
  echo "${EPACE}-sl | --ssl-list"
  echo "${EPACE}${EPACE} list all ssl"
  echo "${EPACE}-sa | --ssl-add [domain_name]"
  echo "${EPACE}${EPACE} add ssl to a website"
  echo "${EPACE}-sd | --ssl-delete [domain_name]"
  echo "${EPACE}${EPACE} delete ssl from a website"
  echo -e "\033[1mQUICK OPTIONS\033[0m"
  echo "${EPACE}-qa | --quick-add [domain_name]"
  echo "${EPACE}${EPACE} add website, database, ssl, restart server"
  echo -e "\033[1mADVANCED OPTIONS\033[0m"
  echo "${EPACE}-wc | --warm-cache [domain_name]"
  echo "${EPACE}${EPACE} loads a website sitemap and visits each page, used to warm the cache"
  echo -e "\033[1mGENERAL OPTIONS\033[0m"
  echo "${EPACE}--up | --start | --init"
  echo "${EPACE}${EPACE} start xshok-webserver (will launch docker-compose.yml)"
  echo "${EPACE}--down | --stop"
  echo "${EPACE}${EPACE} stop all dockers and docker-compose"
  echo "${EPACE}-r | --restart"
  echo "${EPACE}${EPACE} gracefully restart openlitespeed with zero down time"
  echo "${EPACE}-b | --boot | --service | --systemd"
  echo "${EPACE}${EPACE} creates a systemd service to start docker and run docker-compose.yml on boot"
  echo "${EPACE}-p | --password"
  echo "${EPACE}${EPACE} generate and set a new web-admin password"
  echo "${EPACE}-e | --env"
  echo "${EPACE}${EPACE} generate a new .env from the default.env"
  echo "${EPACE}-H, --help"
  echo "${EPACE}${EPACE}Display help and exit."
}

if [ -z "${1}" ]; then
  help_message
  exit 1
fi
while [ ! -z "${1}" ]; do
  case ${1} in
    -[hH] | --help )
      help_message
      ;;
      # -da | --domain-add | --domainadd ) shift
      #     xshok_domain_add ${1}
      #     ;;
      # -dd | --domain-delete | --domaindelete ) shift
      #     xshok_domain_delete ${1}
      #     ;;
      ## WEBSITE
    -wl | --website-list | --websitelist )
      xshok_website_list
      ;;
    -wa | --website-add | --websiteadd )
      xshok_check_s2 "$2";
      xshok_website_add "$2"
      xshok_restart
      shift
      ;;
    -wd | --website-delete | --websitedelete )
      xshok_check_s2 "$2";
      xshok_website_delete "$2"
      xshok_restart
      shift
      ;;
    -wp | --website-permissions | --websitepermissions )
      xshok_check_s2 "$2";
      xshok_website_permissions "$2"
      shift
      ;;
      ## DATABASE
    -dl | --database-list | --databaselist)
      xshok_check_s2 "$2";
      xshok_database_list "$2"
      shift
      ;;
    -da | --database-add | --databaseadd)
      xshok_check_s2 "$2";
      xshok_database_add "$2"
      shift
      ;;
    -dd | --database-delete | --databasedelete)
      xshok_check_s2 "$2";
      xshok_database_delete "$2"
      shift
      ;;
    -dp | --database-password | --databasepassword)
      xshok_check_s2 "$2";
      xshok_database_password "$2"
      shift
      ;;
    -dr | --database-restore | --databaserestore)
      xshok_check_s2 "$2";
      xshok_check_s2 "$3";
      xshok_database_restore "$2" "$3"
      shift 2
      ;;
      ## BACKUP
    -bd | --backup-database | --backupdatabase)
      xshok_check_s2 "$2";
      xshok_check_s2 "$3";
      xshok_backup_database "$2" "$3"
      shift 2
      ;;
    -ba | --backup-all | --backupall)
      xshok_backup_all_database "$2"
      shift
      ;;
      ## SSL
    -sl | --ssl-list | --ssllist )
      xshok_ssl_list
      ;;
    -sa | --ssl-add | --ssladd )
      xshok_check_s2 "$2";
      xshok_ssl_add "$2"
      shift
      ;;
    -sd | --ssl-delete | --ssldelete )
      xshok_check_s2 "$2";
      xshok_ssl_delete "$2"
      shift
      ;;
      ## QUICK
    -qa | --quick-add | --quickadd )
      xshok_check_s2 "$2";
      xshok_website_add "$2"
      xshok_database_add "$2"
      xshok_ssl_add "$2"
      xshok_restart
      shift
      ;;
      ## ADVANCED
    -wc | --warm-cache | --warmcache )
      xshok_check_s2 "$2";
      xshok_website_warm_cache "$2"
      shift
      ;;
      ## GENERAL
    --up | --start | --init )
      xshok_docker_up
      shift
      ;;
    --down | --stop )
      xshok_docker_down
      shift
      ;;
    -r | --restart )
      xshok_restart
      shift
      ;;
    -b | --boot | --service | --systemd )
      xshok_docker_boot
      shift
      ;;
    -p | --password )
      xshok_password
      shift
      ;;
    -e | --env )
      xshok_env
      shift
      ;;
    *)
      help_message
      ;;
  esac
  shift
done

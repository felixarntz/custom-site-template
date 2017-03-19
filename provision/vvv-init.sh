#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".dev`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*]/}

WP_PLUGINS=(`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.wp_plugins 2> /dev/null`)
GIT_PLUGINS=(`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.git_plugins 2> /dev/null`)

WP_THEMES=(`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.wp_themes 2> /dev/null`)
GIT_THEMES=(`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.git_themes 2> /dev/null`)

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# Install and configure the latest stable version of WordPress
if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
    echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.dev" --admin_password="password"

  noroot wp plugin uninstall akismet --quiet
  noroot wp plugin uninstall hello --quiet
  noroot wp comment delete 1 --force --quiet
  noroot wp post delete 1 --force --quiet
else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"
fi

for i in "${WP_PLUGINS[@]}"
do :
  if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/$i" ]]; then
    echo "Installing plugin $i from wordpress.org..."
    noroot wp plugin install $i --quiet
  else
    echo "Updating plugin $i from wordpress.org..."
    noroot wp plugin update $i --quiet
  fi
done

for j in "${GIT_PLUGINS[@]}"
do :
  if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/$j" ]]; then
    echo "Installing plugin $j from github.com..."
    noroot git clone git@github.com:felixarntz/$j.git ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/$j --quiet
  else
    echo "Updating plugin $j from github.com..."
    cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/$j
    noroot git pull --quiet
  fi
done

for k in "${WP_THEMES[@]}"
do :
  if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/themes/$k" ]]; then
    echo "Installing theme $k from wordpress.org..."
    noroot wp theme install $k --quiet
  else
    echo "Updating theme $k from wordpress.org..."
    noroot wp theme update $k --quiet
  fi
done

for l in "${GIT_THEMES[@]}"
do :
  if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/themes/$l" ]]; then
    echo "Installing theme $l from github.com..."
    noroot git clone git@github.com:felixarntz/$l.git ${VVV_PATH_TO_SITE}/public_html/wp-content/themes/$l --quiet
  else
    echo "Updating theme $l from github.com..."
    cd ${VVV_PATH_TO_SITE}/public_html/wp-content/themes/$l
    noroot git pull --quiet
  fi
done

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

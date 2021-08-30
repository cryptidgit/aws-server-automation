#!/bin/bash

#######################################################################################
# OPTION PROCESSING

while getopts "he:n:u:d:" option; do
  case $option in
    h) # Display options with explanations
       echo "automateServer syntax: automateServer [-h|e|n|u] -d domain [-d domain]"
       echo "Options:"
       echo "-h Display script options"
       echo "-e Specify email for Let's Encrypt to contact"
       echo "-n Specify wordpress database name"
       echo "-u Specify wordpress username"
       echo "-d Specify domain(s) to be added to server"
       exit
       ;;
    
    e) # Set contact email for Let's Encrypt
       email=$OPTARG
       ;;

    n) # Set wordpress database name
       dbname=$OPTARG
       ;;
    
    u) # Set wordpress username
       wpname=$OPTARG
       ;;

    d) # Retrieve domain names
       domain+=("$OPTARG")
       ;;

    \?) # Handle invalid options
        echo "See automateServer -h for help"
        exit
        ;;
  esac
done



#######################################################################################

# Exit script if no domain is provided 
if [[ $* != *-d* ]];
then 
  echo "Syntax error: bash automateServer.sh -d domain"
  exit
fi

# Initialize default variables if not initialized with options
if [ -z "$email" ];
then
  email=hosting@4sitestudios.com
fi

if [ -z "$dbname" ];
then
  dbname=wordpress
fi

if [ -z "$wpname" ];
then
  wpname=wordpressuser
fi

#if [ -z "$tprefix" ];
#then
#  tprefix=wp_
#fi

# Generate password for MySQL database
passgen=$(openssl rand -hex 12 | md5sum)
password=${passgen%???}


sudo apt-get --assume-yes  update 

# Install NGINX 
sudo apt-get --assume-yes  install nginx

sudo ufw --force enable
sudo ufw allow 'Nginx Full'
sudo ufw allow 'OpenSSH'

# Install MySQL
sudo apt-get --assume-yes install mysql-server

# Manually perform mysql_secure_installation
sudo mysql <<EOF
DELETE FROM mysql.user WHERE User=''; 
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); 
DROP DATABASE test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF

# Install PHP
sudo apt-get --assume-yes install php-fpm php-mysql

# Create MySQL Database and User for Wordpress
sudo mysql <<EOF
CREATE DATABASE $dbname DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER '$wpname'@'localhost' IDENTIFIED BY '$password';
GRANT ALL ON $dbname.* TO '$wpname'@'localhost';
FLUSH PRIVILEGES;
EOF

# Install PHP Extensions for Wordpress
sudo apt-get --assume-yes update
sudo apt-get --assume-yes install php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip
sudo systemctl restart php7.4-fpm

# Configure Nginx
sudo mkdir /var/www/$domain
sudo chown -R $USER:$USER /var/www/$domain

sudo cat > testfile <<EOF
server {
    listen 80;
    server_name ${domain[@]};
    root /var/www/$domain;

    index index.html index.htm index.php;

    location / {
        #try_files  / =404;
        try_files $uri $uri/ /index.php$is_args$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
     }

    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt { log_not_found off; access_log off; allow all; }
    location ~* \.(css|gif|ico|jpeg|jpg|js|png)$ {
        expires max;
        log_not_found off;
    }

}
EOF
sudo cp testfile /etc/nginx/sites-available/$domain
sudo rm testfile

sudo ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
sudo unlink /etc/nginx/sites-enabled/default

sudo sed -i "s/# server_names_hash_bucket_size 64;/server_names_hash_bucket_size 64;/g" /etc/nginx/nginx.conf

sudo systemctl reload nginx

# Obtain SSL Certificate for Nginx Server
sudo apt-get --assume-yes install certbot python3-certbot-nginx
# if [ $(sudo certbot certificates | grep -c "Found the following certs") -eq 0 ];
# then
#  for val in "${domain[@]}"; do
#    sudo certbot --noninteractive --nginx --agree-tos -d $val -m $email
#  done
# fi

# Download WordPress
cd /tmp
curl -LO https://wordpress.org/latest.tar.gz

tar xzvf latest.tar.gz

cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php
sudo cp -a /tmp/wordpress/. /var/www/$domain
sudo chown -R www-data:www-data /var/www/$domain

# Create modified config file
head -n 22 /var/www/$domain/wp-config.php > newfile

# Copy database info into modified config file
cat << EOF >> newfile
define( 'DB_NAME', '$dbname' );

/** MySQL database username */
define( 'DB_USER', '$wpname' );

/** MySQL database password */
define( 'DB_PASSWORD', '$password' );

/** MySQL hostname */
define( 'DB_HOST', 'localhost' );

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

define( 'FS_METHOD', 'direct' );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
EOF

# Add salt keys to config file
curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> newfile  

# Add end of config file
cat << EOF >> newfile

/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define( 'WP_DEBUG', false );

/* Add any custom values between this line and the "stop editing" line. */



/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
        define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
EOF

# Overwrite original config file with modified config file
sudo cp newfile /var/www/$domain/wp-config.php
rm newfile

# Fix disappearing variables
sudo sed -i 's|try_files  / /index.php;|try_files $uri $uri/ /index.php$is_args$args;|g' /etc/nginx/sites-available/$domain
sudo sed -i "70 a \$table_prefix = 'wp_';" /var/www/$domain/wp-config.php
sudo sed -i '70d' /var/www/$domain/wp-config.php

# Create swap file
sudo fallocate -l 1G /swapfile

sudo chmod 600 /swapfile

sudo mkswap /swapfile

sudo swapon /swapfile

sudo sed -i '1 a /swapfile swap swap defaults 0 0' /etc/fstab

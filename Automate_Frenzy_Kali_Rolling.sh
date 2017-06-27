#!/bin/bash

FQDN="phishing-frenzy.local"
CURRENTIP="$(hostname -i)"
RVERSION="2.3.0"
RAILVERSION="4.2.5"

echo "Cloning the GIT "
git clone https://github.com/pentestgeek/phishing-frenzy.git /var/www/phishing-frenzy

echo "Trying to install All the dependencies …"
\curl -sSL https://get.rvm.io | bash
source /etc/profile.d/rvm.sh
rvm pkg install openssl
rvm install $RVERSION --with-openssl-dir=/usr/local/rvm/usr
rvm all do gem install --no-rdoc --no-ri rails -v $RAILVERSION
rvm all do gem install --no-rdoc --no-ri passenger

echo "[*] Install Passenger …"
apt-get update
apt-get install -y apache2-dev libcurl4-openssl-dev
leafpad /etc/apache2/apache2.conf &

echo -e "\nYou have to edit the apache2.conf file after the passenger installation"
read -p "Press [Enter] key to continue."

passenger-install-apache2-module --languages ruby

echo "[*] VHOST Configuration …"
echo >> /etc/apache2/apache2.conf
echo "Include pf.conf" >> /etc/apache2/apache2.conf

apt-get install -y libmysqlclient-dev
echo -e "\n if the Libmysqlclient-dev fails - add the right repo to the /etc/apt/sources.lst"

touch /etc/apache2/pf.conf

PASSENGERDIR=$(ls -1 -d $GEM_HOME/gems/passenger*)

# 'PassengerRoot' and 'PassengerRuby' values should follow the ones in apache2.conf

cat > /etc/apache2/pf.conf << EOL
  <IfModule mod_passenger.c>
    PassengerRoot $PASSENGERDIR
    PassengerRuby $GEM_HOME/wrappers/ruby
  </IfModule>

  <VirtualHost *:80>
    ServerName $FQDN
    # !!! Be sure to point DocumentRoot to 'public'!
    DocumentRoot /var/www/phishing-frenzy/public
    RailsEnv development
    <Directory /var/www/phishing-frenzy/public>
      # This relaxes Apache security settings.
      AllowOverride all
      # MultiViews must be turned off.
      Options -MultiViews
    </Directory>
  </VirtualHost>
EOL

echo "starting MySQL …"
service mysql start
# kali by default uses blank mysql root passwords
mysql -uroot --password="" -e "create database pf_dev"
mysql -uroot --password="" -e "grant all privileges on pf_dev.* to 'pf_dev'@'localhost' identified by 'password'"

echo "Installing all the required GEMS, might take a while - if failed re-run …"
cd /var/www/phishing-frenzy/
bundle install --deployment
bundle exec rake db:migrate
bundle exec rake db:seed

echo "Installing Redis …"
wget http://download.redis.io/releases/redis-stable.tar.gz
tar xzf redis-stable.tar.gz
cd redis-stable/
make
make install
cd utils/
echo -n | ./install_server.sh

echo "Installing sidekiq…"
mkdir -p /var/www/phishing-frenzy/tmp/pids
cd /var/www/phishing-frenzy
bundle exec sidekiq -C config/sidekiq.yml &

echo "Setting the permissions hold on …"
echo "www-data ALL=(ALL) NOPASSWD: /etc/init.d/apache2 reload" >> /etc/sudoers
bundle exec rake templates:load
chown -R www-data:www-data /var/www/phishing-frenzy/
chmod -R 755 /var/www/phishing-frenzy/public/uploads/
chown -R www-data:www-data /etc/apache2/sites-enabled/
chmod -R 755 /etc/apache2/sites-enabled/
chown -R www-data:www-data /etc/apache2/sites-available/

echo "$CURRENTIP $FQDN"  >> /etc/hosts

apachectl start

echo "Login with admin : Funt1me!"
/etc/alternatives/x-www-browser "http://$FQDN" &

#!/bin/bash -
###############################################################################
# File:			build-gitorious.sh
#
# Description:          Script to build Gitorious from source
#
# Author:		John Tregoning
#
###############################################################################


# ONLY CHANGE THIS PART
export SERVER_NAME=192.168.1.74
export PASSWORD_STRING=pa55word
export GITORIUOS_SUPPORT_EMAIL=email@here.com


# DO NOT CHANGE THIS PART
#Initial setup
rpm -Uvh http://download.fedora.redhat.com/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm

#Ensuring YUM is up to date
yum clean metadata
yum clean dbcache
yum -y update

#Installing pre-required software
yum -y install git-core git-svn pcre pcre-devel zlib zlib-devel sendmail wget
yum -y groupinstall "Development Libraries" "Development Tools"
yum -y install libssh2 libssh2-devel openssh openssh-server memcached libyaml libyaml-devel ImageMagick ImageMagick-devel apr-devel uuid java-1.6.0-openjdk readline-devel glibc-devel openssl-devel gcc-c++ gcc-c++ zlib-devel readline-devel sphinx apg

#Install and Configure MySQL 
yum -y install mysql mysql-server mysql-devel mysql++-devel mysql++
chkconfig --add mysqld
chkconfig mysqld on
service mysqld start
##Replaced with your own password
mysqladmin -u root password "${PASSWORD_STRING}"

#Installing Oniguruma
wget http://www.geocities.jp/kosako3/oniguruma/archive/onig-5.9.1.tar.gz
tar xvfz onig-5.9.1.tar.gz
cd onig-5.9.1
./configure
make && make install

#Ruby Enterprise Edition
cd /tmp
wget http://rubyforge.org/frs/download.php/71096/ruby-enterprise-1.8.7-2010.02.tar.gz
tar xzvf ruby-enterprise-1.8.7-2010.02.tar.gz
./ruby-enterprise-1.8.7-2010.02/installer --auto=/opt/ruby-enterprise-1.8.7-2010.02
cd /opt/
ln -s /opt/ruby-enterprise-1.8.7-2010.02 /opt/ruby-enterprise
cd /tmp

##Setting up variables for Ruby/Rails
##Need to check that this is an appropriate place to set RAILS_ENV
echo 'export PATH=/opt/ruby-enterprise/bin:$PATH
export LD_LIBRARY_PATH="/usr/local/lib"
export LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" 
export RUBY_HOME=/opt/ruby-enterprise
export RAILS_ENV=production
export GEM_HOME=$RUBY_HOME/lib/ruby/gems/1.8
export PATH=$GEM_HOME/bin:$PATH
export PATH=$RUBY_HOME/bin:$PATH' > /etc/profile.d/ruby.sh
source /etc/profile.d/ruby.sh

#Required Gems
gem update --system
gem install --no-ri --no-rdoc rails mongrel mime-types textpow chronic ruby-hmac daemons mime-types oniguruma textpow passenger chronic BlueCloth ruby-yadis ruby-openid geoip ultrasphinx rspec rspec-rails RedCloth echoe hoe diff-lcs stompserver json ultrasphinx RedCloth
##Latest version of rack wasn’t compatible with our testing environment, you may need to use version 1.0.1 instead.
gem install --no-ri --no-rdoc -v 1.0.1 rack
##Also need these specific versions...
gem install --no-ri --no-rdoc -v 1.1 stomp
gem install --no-ri --no-rdoc -v 1.3.1.1 rdiscount

#Uninstall some Gems
echo "Y"| gem uninstall i18n

##Installing extra gems that were not installed
gem install mysql -- --with-mysql-config='/usr/bin/mysql_config'

#Install Apache
yum install -y httpd httpd-devel

#Install also the mod_xsendfile module to get source tarball downloading working.
cd /tmp
wget http://tn123.ath.cx/mod_xsendfile/mod_xsendfile.c --no-check-certificate
apxs -cia mod_xsendfile.c

#Install Apache Modules
yum install -y mod_ssl

#Installing apxs - APache eXtenSion tool
yum -y install httpd-devel.x86_64

#Clone the Gitorious Repository 
cd /var/www
git clone git://gitorious.org/gitorious/mainline.git gitorious
ln -s /var/www/gitorious/script/gitorious /usr/local/bin/gitorious

#Install Phusion Passenger module to simplify Rails application deployment.
/opt/ruby-enterprise/bin/passenger-install-apache2-module --auto

#Apache configuration update
sed -ie '207i\LoadModule passenger_module /opt/ruby-enterprise/lib/ruby/gems/1.8/gems/passenger-3.0.0/ext/apache2/mod_passenger.so' /etc/httpd/conf/httpd.conf
sed -ie '208i\PassengerRoot /opt/ruby-enterprise/lib/ruby/gems/1.8/gems/passenger-3.0.0' /etc/httpd/conf/httpd.conf
sed -ie '209i\PassengerRuby /opt/ruby-enterprise/bin/ruby' /etc/httpd/conf/httpd.conf
sed -ie '210i\XSendFile on' /etc/httpd/conf/httpd.conf
sed -ie '211i\RewriteEngine on' /etc/httpd/conf/httpd.conf

sed -ie 's/^DocumentRoot "\/var\/www\/html"$/DocumentRoot "\/var\/www\/gitorious\/public"/' /etc/httpd/conf/httpd.conf
sed -ie 's/^<Directory "\/var\/www\/html">$/<Directory "\/var\/www\/gitorious\/public">/' /etc/httpd/conf/httpd.conf
sed -ie "s/^#ServerName www.example.com:80$/ServerName ${SERVER_NAME}/" /etc/httpd/conf/httpd.conf

#Create & and set up git user
adduser --create-home git

#Create the Directories for Repositories and Tarballs 
mkdir -p /var/www/gitorious/public/git/tarballs  
mkdir -p /var/www/gitorious/public/git/tarball-work
mkdir -p /var/git/repositories
mkdir -p /tmp/git-repos/

#Setting owner for the required gitoriuos folders
chown -R git:git /var/www/gitorious /var/git /tmp/git-repos/

#Make authorized_keys File for the git account
su - git -c "mkdir ~/.ssh"
su - git -c "chmod 700 ~/.ssh"
su - git -c "touch ~/.ssh/authorized_keys"
su - git -c "chmod 600 ~/.ssh/authorized_keys"

#make a directory for pid files.
su - git -c "mkdir -p /var/www/gitorious/tmp/pids"
#Make all the Gitorious scripts executable.
su - git -c "chmod ug+x /var/www/gitorious/script/*"

#Copy the configuration sample files and edit the settings
su - git -c "cp /var/www/gitorious/config/database.sample.yml /var/www/gitorious/config/database.yml"
su - git -c "cp /var/www/gitorious/config/gitorious.sample.yml /var/www/gitorious/config/gitorious.yml"
su - git -c "cp /var/www/gitorious/config/broker.yml.example /var/www/gitorious/config/broker.yml"

#Setting up database.yml
su - git -c "sed -ie 's/password:/password: ${PASSWORD_STRING}/' /var/www/gitorious/config/database.yml"

#Setting up gitorious.yml
export SECRET=`apg -m 64 | tr -d '\n"%'`
sed -ie "s/cookie_secret\:.*$/cookie_secret\: $SECRET/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/repository_base_path\:.*$/repository_base_path\: \/var\/git\/repositories/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/public_mode\:.*$/public_mode\: true/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/gitorious_client_port\:.*/gitorious_client_port\: 80/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/gitorious_client_host\:.*/gitorious_client_host\: ${SERVER_NAME}/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/gitorious_host\:.*$/gitorious_host\: ${SERVER_NAME}/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/gitorious_support_email\:.*$/gitorious_support_email\: ${GITORIUOS_SUPPORT_EMAIL}/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/archive_cache_dir\:.*$/archive_cache_dir\: \"\/var\/www\/gitorious\/public\/git\/tarballs\"/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/archive_work_dir\:.*$/archive_work_dir\: \"\/var\/www\/gitorious\/public\/git\/tarball-work\"/" /var/www/gitorious/config/gitorious.yml
sed -ie "s/^public_mode: false$/public_mode: true/" /var/www/gitorious/config/gitorious.yml
sed -ie "3 s/production:/test:/" /var/www/gitorious/config/gitorious.yml
sed -ie "5 s/test:/production:/" /var/www/gitorious/config/gitorious.yml
chown git:git /var/www/gitorious/config/gitorious.yml

#Install the remaining gems:
cd /var/www/gitorious
sudo rake gems:install RAILS_ENV=production

#Create the database and schema:
rake db:create RAILS_ENV=production
rake db:migrate RAILS_ENV=production

#Build the search index and start the search daemon:
rake ultrasphinx:configure RAILS_ENV=production
rake ultrasphinx:index RAILS_ENV=production  
rake ultrasphinx:daemon:start RAILS_ENV=production

#Solving permission issues on log & db/sphinx
chown -R git:git /var/www/gitorious

#Schedule Sphinx search engine to index the site automatically. Add to the crontab, using crontab -e, the following line:
su - git -c "crontab -l > /tmp/cron.txt"
echo "* * * * * cd /var/www/gitorious && /opt/ruby-enterprise/bin/rake ultrasphinx:index RAILS_ENV=production" >> /tmp/cron.txt
su - git -c "crontab /tmp/cron.txt"

# init.d scripts
cp /var/www/gitorious/doc/templates/centos/git-daemon /etc/init.d/git-daemon
cp /var/www/gitorious/doc/templates/centos/git-ultrasphinx /etc/init.d/git-ultrasphinx
cp /var/www/gitorious/doc/templates/centos/gitorious-logrotate /etc/logrotate.d/gitorious-logrotate
chmod 644 /etc/logrotate.d/gitorious-logrotate

#Creating gitorious-poller script
echo '#!/bin/sh
#  
# poller       Startup script for Gitorious-s poller  
#  
# chkconfig: - 86 15  
# description: Gitorious-s poller script is simple worker that polls  
#              tasks from stomp server queue and executes them.  
# processname: poller

/bin/su - git -c "cd /var/www/gitorious; RAILS_ENV=production ./script/poller $@"' > /etc/init.d/gitorious-poller

#Creating stomp script
echo '---
:daemon: true
:working_dir: /tmp/stompserver
:storage: .queue
:queue: file
:auth: false
:debug: false
:group:
:user:
:host: 127.0.0.1
:port: 61613' > /etc/stompserver.conf

echo '#!/bin/sh
#  
# stomp        Startup script for stomp server   
#  
# chkconfig: - 85 15  
# description: Stomp server is simple task queue server that
#              uses stomp protocol.       
# processname: stomp  
# config: /etc/stompserver.conf

/bin/su - git -c "cd /var/www/gitorious; RAILS_ENV=production; stompserver -C /etc/stompserver.conf $@"' > /etc/init.d/stomp

#give the scripts execute permissions
cd /etc/init.d/
sudo chmod 755 git-daemon git-ultrasphinx gitorious-poller stomp

#Add services to start automatically on boot
chkconfig --add stomp
chkconfig --add git-daemon  
chkconfig --add gitorious-poller  
chkconfig --add git-ultrasphinx  
chkconfig --add memcached
chkconfig --add httpd

chkconfig stomp on  
chkconfig git-daemon on  
chkconfig gitorious-poller on  
chkconfig git-ultrasphinx on  
chkconfig memcached on
chkconfig httpd on

#starting the services:
service git-ultrasphinx start
service stomp start  
service memcached start  
service gitorious-poller start  
service git-daemon start  
service httpd start

#Update ip-tables
iptables -D RH-Firewall-1-INPUT -j REJECT --reject-with icmp-host-prohibited
iptables -A RH-Firewall-1-INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
iptables -A RH-Firewall-1-INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
iptables -A RH-Firewall-1-INPUT -p tcp -m state --state NEW -m tcp --dport 9418 -j ACCEPT
iptables -A RH-Firewall-1-INPUT -j REJECT --reject-with icmp-host-prohibited
service iptables save

#Clearing History for security reasons
history -c

#Now you should have Gitorious up and running! Go to your web page through a browser and start using Gitorious.

#TODO:
#RewriteEngine On ??
#XSendFilePath instead of XSendFileAllowAbove
#script/shard_git_repositories_by_hash
#Aspell error message
#gem_dependency.rb:119:Warning: Gem::Dependency#version_requirements is deprecated and will be removed on or after August 2010


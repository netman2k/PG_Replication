#!/bin/bash
echo "### Running bootstrap.sh ###"

echo "Installing VIM..."
rpm -qi vim-enhanced &> /dev/null || yum -y install vim-enhanced


[ -f /etc/yum.repos.d/pgdg-93-redhat.repo ] || {
	echo "Installing yum repo..."
	yum -y install http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-redhat93-9.3-1.noarch.rpm
}

echo "Installing PostgreSQL..."
rpm -qi postgresql93-server &> /dev/null || yum -y install postgresql93-server

if [ `hostname` == 'app' ];then
	rpm -qi nfs-utils &> /dev/null || {
		echo "Remove conflict nfs-utils package"
		yum -y remove nfs-utils
	}

	echo "Installing PGPool-II..."
	rpm -qi pgpool-II-93 &> /dev/null || yum -y install pgpool-II-93
fi

echo "Setting /etc/hosts..."
cat <<EOF > /etc/hosts
127.0.0.1 localhost
192.168.200.2 master
192.168.200.3 slave1
192.168.200.4 slave2
192.168.200.5 app
EOF

echo "Copying own SSH Keys..."
cp -vr /vagrant/keys/`hostname`/.ssh ~postgres/ && chown -R postgres: ~postgres/.ssh 

# Copy master server and app(pgpool) keys to every slaves
echo "Copying others SSH keys..."
# preparing an authorized_keys file
[ -f ~postgres/.ssh/authorized_keys ] && rm ~postgres/.ssh/authorized_keys
touch ~postgres/.ssh/authorized_keys
chown postgres: ~postgres/.ssh/authorized_keys 

if [[ `hostname` == slave* ]];then

	# Copy master and pgpool server key to every slaves
	grep -q "postgres@master" ~postgres/.ssh/authorized_keys || \
		cat /vagrant/keys/master/.ssh/id_rsa.pub >> ~postgres/.ssh/authorized_keys
	grep -q "postgres@app" ~postgres/.ssh/authorized_keys || \
		cat /vagrant/keys/app/.ssh/id_rsa.pub >> ~postgres/.ssh/authorized_keys

	# Copy failover server key to every slaves
	if [[ `hostname` != 'slave1' ]];then
		grep -q "postgres@slave1" ~postgres/.ssh/authorized_keys || \
			cat /vagrant/keys/slave1/.ssh/id_rsa.pub >> ~postgres/.ssh/authorized_keys
	fi

	chown postgres: ~postgres/.ssh/authorized_keys
fi

if [ `hostname` == 'master' ];then
	grep -q "postgres@slave1" ~postgres/.ssh/authorized_keys || \
		cat /vagrant/keys/slave1/.ssh/id_rsa.pub >> ~postgres/.ssh/authorized_keys
	grep -q "postgres@app" ~postgres/.ssh/authorized_keys || \
		cat /vagrant/keys/app/.ssh/id_rsa.pub >> ~postgres/.ssh/authorized_keys

	chown postgres: ~postgres/.ssh/authorized_keys
fi

echo "Disabling Host key checking..."
[ -f ~postgres/.ssh/config ] && rm ~postgres/.ssh/config
cat <<EOF > ~postgres/.ssh/config
Host *
	StrictHostKeyChecking no
EOF
chown postgres: ~postgres/.ssh/config

echo "Initializing & start database..."
service postgresql-9.3 initdb && service postgresql-9.3 start 

echo "Create backup the configuration files..."
mv ~postgres/9.3/data/postgresql.conf{,.back}
mv ~postgres/9.3/data/pg_hba.conf{,.back}

if [ `hostname` != 'app' ];then
	echo "Setting postgresql.conf..."
	cp -vr /vagrant/postgresql/`hostname`/postgresql.conf ~postgres/9.3/data/ && chown -R postgres: ~postgres/9.3/data/postgresql.conf

	echo "Setting pg_hba.conf..."
	cp -vr /vagrant/postgresql/`hostname`/pg_hba.conf ~postgres/9.3/data/ && chown -R postgres: ~postgres/9.3/data/pg_hba.conf
fi

echo "Create repl and pgpool accounts..."
if [ `hostname` == 'master' ];then
	sudo su - postgres -c "psql -c \"CREATE USER repl REPLICATION ENCRYPTED PASSWORD 'repl';\""
	sudo su - postgres -c "psql -c \"CREATE USER pgpool LOGIN ENCRYPTED PASSWORD 'pgpool';\""
fi

#service postgresql stop

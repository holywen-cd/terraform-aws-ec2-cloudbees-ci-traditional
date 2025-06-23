#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version

yum install -y wget git

# checkout the casc repo
git clone

# install CloudBees Core Operations Center
wget -O /etc/yum.repos.d/cloudbees-core-oc.repo https://downloads.cloudbees.com/cloudbees-core/traditional/operations-center/rolling/rpm/cloudbees-core-oc.repo
rpm --import "https://downloads.cloudbees.com/cloudbees-core/traditional/operations-center/rolling/rpm/cloudbees.com.key"

dnf -y upgrade
dnf install -y cloudbees-core-oc

cat <<EOF > /var/lib/cloudbees-core-oc/license.xml
${license_file_content}
EOF





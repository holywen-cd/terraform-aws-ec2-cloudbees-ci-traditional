#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version

yum install -y wget curl

# install CloudBees Core Client Controller
wget -O /etc/yum.repos.d/cloudbees-core-cm.repo https://downloads.cloudbees.com/cloudbees-core/traditional/client-master/rolling/rpm/cloudbees-core-cm.repo
rpm --import "https://downloads.cloudbees.com/cloudbees-core/traditional/client-master/rolling/rpm/cloudbees.com.key"

dnf -y upgrade --nobest

dnf install -y cloudbees-core-cm
systemctl stop cloudbees-core-cm
rm -fr /var/lib/cloudbees-core-cm/*

# configure variables
CONFIG_FILE="/etc/sysconfig/cloudbees-core-cm"
JENKINS_HOME="/var/lib/cloudbees-core-cm"
#CASC_OPTION="--add-exports=java.base/jdk.internal.ref=ALL-UNNAMED --add-modules=java.se --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.management/sun.management=ALL-UNNAMED --add-opens=jdk.management/com.sun.management.internal=ALL-UNNAMED -Djenkins.model.Jenkins.crumbIssuerProxyCompatibility=true -DexecutableWar.jetty.disableCustomSessionIdCookieName=true -Dcom.cloudbees.jenkins.ha=false -Dcom.cloudbees.jenkins.replication.warhead.ReplicationServletListener.enabled=true -XX:+AlwaysPreTouch -XX:+UseStringDeduplication -XX:+ParallelRefProcEnabled -XX:+DisableExplicitGC -Dcore.casc.config.bundle=$${JENKINS_HOME}/bundle-link.yml"
CASC_OPTION="-Dcore.casc.config.bundle=$${JENKINS_HOME}/bundle-link.yml"

# check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# check if the configuration already contains the CasC bundle option
if grep -q "core.casc.config.bundle" "$CONFIG_FILE"; then
  echo "Already configured: 'core.casc.config.bundle' exists in $CONFIG_FILE"
else
  echo "Adding CasC bundle option to $CONFIG_FILE"

  # append the CasC bundle option to the configuration file
  if grep -q "^JENKINS_JAVA_OPTIONS=" "$CONFIG_FILE"; then
    sed -i "/^JENKINS_JAVA_OPTIONS=/ s|\"$| $${CASC_OPTION}\"|" "$CONFIG_FILE"
  else
    echo "JENKINS_JAVA_OPTIONS=\"$${CASC_OPTION}\"" >> "$CONFIG_FILE"
  fi
fi

echo "Updated $CONFIG_FILE with CasC bundle path"

#wait until oc is ready
while true; do
  if wget --spider -q ${oc_url}/login; then
    echo "OC is up"
    break
  else
    echo "⏱ Waiting for OC..."
    sleep 5
  fi
done

#download bundle-link file
cd $${JENKINS_HOME} && curl --user '${oc_login_user}:${oc_login_pwd}' -XGET '${oc_url}/config-bundle-download-link/?id=ha' > bundle-link.yml

systemctl start cloudbees-core-cm

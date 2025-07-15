#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version

yum install -y wget curl

#mount efs
yum install -y nfs-utils

echo "Waiting for DNS resolution of ${efs_dns} ..."

while ! getent hosts "${efs_dns}" > /dev/null 2>&1; do
  echo "DNS not ready for ${efs_dns}, retrying in 5 seconds..."
  sleep 5
done

echo "DNS resolved successfully:"
getent hosts "${efs_dns}"

mkdir -p /mnt/efs
mount -t nfs4 -o _netdev,rw,bg,hard,intr,rsize=32768,wsize=32768,vers=4.1,proto=tcp,timeo=600,retrans=2,noatime,nodiratime,async ${efs_dns}:/ /mnt/efs

#automount /etc/fstab
echo "${efs_dns}:/ /mnt/efs nfs4 _netdev,rw,bg,hard,intr,rsize=32768,wsize=32768,vers=4.1,proto=tcp,timeo=600,retrans=2,noatime,nodiratime,async 0 0" >> /etc/fstab

# install CloudBees Core Client Controller
wget -O /etc/yum.repos.d/cloudbees-core-cm.repo https://downloads.cloudbees.com/cloudbees-core/traditional/client-master/rolling/rpm/cloudbees-core-cm.repo
rpm --import "https://downloads.cloudbees.com/cloudbees-core/traditional/client-master/rolling/rpm/cloudbees.com.key"

dnf -y upgrade --nobest

dnf install -y cloudbees-core-cm
chown -R cloudbees-core-cm:cloudbees-core-cm /mnt/efs
systemctl stop cloudbees-core-cm
rm -fr /var/lib/cloudbees-core-cm/*

# configure variables
CONFIG_FILE="/etc/sysconfig/cloudbees-core-cm"
JENKINS_HOME="/mnt/efs"
CASC_OPTION="--add-exports=java.base/jdk.internal.ref=ALL-UNNAMED --add-modules=java.se --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.management/sun.management=ALL-UNNAMED --add-opens=jdk.management/com.sun.management.internal=ALL-UNNAMED -Djenkins.model.Jenkins.crumbIssuerProxyCompatibility=true -DexecutableWar.jetty.disableCustomSessionIdCookieName=true -Dcom.cloudbees.jenkins.ha=false -Dcom.cloudbees.jenkins.replication.warhead.ReplicationServletListener.enabled=true -XX:+AlwaysPreTouch -XX:+UseStringDeduplication -XX:+ParallelRefProcEnabled -XX:+DisableExplicitGC -Dcore.casc.config.bundle=$${JENKINS_HOME}/bundle-link.yml"
#CASC_OPTION="-Dcore.casc.config.bundle=$${JENKINS_HOME}/bundle-link.yml"

# check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

#update JENKINS_HOME in the configuration file
sed -i "s|^JENKINS_HOME=.*|JENKINS_HOME=\"$${JENKINS_HOME}\"|" "$CONFIG_FILE"

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

#check if added CONTROLLER_URL to the config file
if grep -q "CONTROLLER_URL" "$CONFIG_FILE"; then
     echo "Already configured: 'CONTROLLER_URL' exists in $CONFIG_FILE"
   else
     echo "Adding CONTROLLER_URL to $CONFIG_FILE"
     echo "CONTROLLER_URL=\"${cm_url}\"" >> "$CONFIG_FILE"
fi

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

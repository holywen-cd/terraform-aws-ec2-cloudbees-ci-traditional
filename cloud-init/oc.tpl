#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version

yum install -y wget git

git clone https://github.com/holywen-cd/terraform-aws-ec2-cloudbees-ci-traditional /tmp/terraform-aws-ec2-cloudbees-ci-traditional

# install CloudBees Core Operations Center
wget -O /etc/yum.repos.d/cloudbees-core-oc.repo https://downloads.cloudbees.com/cloudbees-core/traditional/operations-center/rolling/rpm/cloudbees-core-oc.repo
rpm --import "https://downloads.cloudbees.com/cloudbees-core/traditional/operations-center/rolling/rpm/cloudbees.com.key"

dnf -y upgrade
dnf install -y cloudbees-core-oc
systemctl stop cloudbees-core-oc
#clean up jenkins home
rm -fr  /var/lib/cloudbees-core-oc/*

mkdir -p /var/lib/cloudbees-core-oc/occascbundle
cp /tmp/terraform-aws-ec2-cloudbees-ci-traditional/casc/cjoc/bundle.yaml /var/lib/cloudbees-core-oc/occascbundle/bundle.yaml
cp /tmp/terraform-aws-ec2-cloudbees-ci-traditional/casc/cjoc/items.yaml /var/lib/cloudbees-core-oc/occascbundle/items.yaml

cat << 'EOF' > /var/lib/cloudbees-core-oc/occascbundle/jenkins.yaml
${oc_jenkins_yaml_content}
EOF

cp /tmp/terraform-aws-ec2-cloudbees-ci-traditional/casc/cjoc/plugins.yaml /var/lib/cloudbees-core-oc/occascbundle/plugins.yaml
cp /tmp/terraform-aws-ec2-cloudbees-ci-traditional/casc/cjoc/rbac.yaml /var/lib/cloudbees-core-oc/occascbundle/rbac.yaml

cat <<EOF > /var/lib/cloudbees-core-oc/license.key
${license_key_content}
EOF

cat <<EOF > /var/lib/cloudbees-core-oc/license.cert
${license_cert_content}
EOF

# configure variables
CONFIG_FILE="/etc/sysconfig/cloudbees-core-oc"
BUNDLE_PATH="/var/lib/cloudbees-core-oc/occascbundle"
JENKINS_HOME="/var/lib/cloudbees-core-oc"
CASC_OPTION="-XX:+AlwaysPreTouch -XX:+UseStringDeduplication -XX:+ParallelRefProcEnabled -XX:+DisableExplicitGC -Dcom.cloudbees.jenkins.ha=false -Dcom.cloudbees.jenkins.ha=false -Dcore.casc.config.bundle=$${BUNDLE_PATH}"

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

systemctl start cloudbees-core-oc



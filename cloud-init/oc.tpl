#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version

yum install -y wget git

# checkout the casc repo
git clone https://github.com/holywen-cd/terraform-aws-ec2-cloudbees-ci-traditional /tmp

# install CloudBees Core Operations Center
wget -O /etc/yum.repos.d/cloudbees-core-oc.repo https://downloads.cloudbees.com/cloudbees-core/traditional/operations-center/rolling/rpm/cloudbees-core-oc.repo
rpm --import "https://downloads.cloudbees.com/cloudbees-core/traditional/operations-center/rolling/rpm/cloudbees.com.key"

dnf -y upgrade
dnf install -y cloudbees-core-oc

mkdir -p /var/lib/cloudbees-core-oc/occascbundle
cat << EOF > /var/lib/cloudbees-core-oc/occascbundle/bundle.yaml
${oc_bundle_yaml_content}
EOF

cat << EOF > /var/lib/cloudbees-core-oc/occascbundle/items.yaml
${oc_items_yaml_content}
EOF

cat << EOF > /var/lib/cloudbees-core-oc/occascbundle/jenkins.yaml
${oc_jenkins_yaml_content}
EOF

cat << EOF > /var/lib/cloudbees-core-oc/occascbundle/plugins.yaml
${oc_plugins_yaml_content}
EOF

cat << EOF > /var/lib/cloudbees-core-oc/occascbundle/rbac.yaml
${oc_rbac_yaml_content}
EOF

cat <<EOF > /var/lib/cloudbees-core-oc/license.key
${license_key_content}
EOF

cat <<EOF > /var/lib/cloudbees-core-oc/license.cert
${license_cert_content}
EOF






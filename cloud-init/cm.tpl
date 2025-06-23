#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version

yum install -y wget

# install CloudBees Core Client Controller
wget -O /etc/yum.repos.d/cloudbees-core-cm.repo https://downloads.cloudbees.com/cloudbees-core/traditional/client-master/rolling/rpm/cloudbees-core-cm.repo
rpm --import "https://downloads.cloudbees.com/cloudbees-core/traditional/client-master/rolling/rpm/cloudbees.com.key"

dnf -y upgrade

dnf install -y cloudbees-core-cm

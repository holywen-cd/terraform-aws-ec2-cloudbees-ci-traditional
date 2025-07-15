#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk

# verify Java installation
java -version


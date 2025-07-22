#!/bin/bash
set -e

# install JDK 21
yum install -y java-21-openjdk wget curl

# verify Java installation
java -version


# connecting as shared agent
useradd -m -d /home/jenkins jenkins

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

echo "------------------  GET AGENT SECRET ------------------"
#see https://docs.cloudbees.com/docs/cloudbees-ci-kb/latest/client-and-managed-controllers/how-to-find-agent-secret-key#_operations_center_shared_agents
echo "def sharedAgent = Jenkins.getInstance().getItems(com.cloudbees.opscenter.server.model.SharedSlave.class).find { it.launcher != null && it.launcher.class.name == 'com.cloudbees.opscenter.server.jnlp.slave.JocJnlpSlaveLauncher' && it.name == 'mySharedAgent'}; return sharedAgent?.launcher.getJnlpMac(sharedAgent)" > agent_secret.groovy

CRUMB=$(curl -s -u '${oc_login_user}:${oc_login_pwd}' --cookie-jar cookies.txt "${oc_url}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

AGENT_SECRET=$(curl --cookie cookies.txt -XPOST --data-urlencode  "script=$(cat ./agent_secret.groovy)" -H "$CRUMB" -L -s --user '${oc_login_user}:${oc_login_pwd}' ${oc_url}/scriptText)
AGENT_SECRET=$(echo $AGENT_SECRET | sed "s#Result: ##g")
echo  "AGENT SECRET: $AGENT_SECRET"

wget ${oc_url}/jnlpJars/agent.jar -O /home/jenkins/agent.jar
mkdir -p /home/jenkins/agent/
chown jenkins:jenkins /home/jenkins/agent/
chown jenkins:jenkins /home/jenkins/agent.jar
sudo -u jenkins bash -c "nohup java -jar /home/jenkins/agent.jar -secret $AGENT_SECRET  -name mySharedAgent -url ${oc_url} -workDir /tmp -webSocket >> /home/jenkins/agent/agent.log 2>&1 &"


jenkins:
  authorizationStrategy: "cloudBeesRoleBasedAccessControl"
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: false
  numExecutors: 1
  securityRealm:
    local:
      allowsSignup: false
      enableCaptcha: false
      users:
      - id: "admin"
        password: ${oc_login_pwd}
        name: ${oc_login_user}
        properties:
        - "consoleUrlProvider"
        - "blueSteelRedirectOptOutProperty"
        - "myView"
        - preferredProvider:
            providerId: "default"
        - "timezone"
        - "experimentalFlags"
        - "apiToken"
        - mailer:
            emailAddress: "user@example.com"
        - "apiToken"
  slaveAgentPort: -1
  updateCenter:
    sites:
    - id: "cap-core-oc-traditional"
      url: "https://jenkins-updates.cloudbees.com/update-center/envelope-core-oc-traditional/update-center.json"
security:
  securitySettingsEnforcement:
    global:
      realmAndAuthorization:
        canCustomMapping: false
        canOverride: false
        defaultMappingFactory: "restrictedEquivalentRAMF"
license:
  certificate: |
    $${readFile:$${JENKINS_HOME}/license.cert}
  key: |
    $${readFile:$${JENKINS_HOME}/license.key}
unclassified:
  bundleStorageService:
    activated: true
    bundles:
      - name: "controller_bundles"
        retriever:
          SCM:
            scmSource:
              git:
                id: "acf88621-05a0-4d50-9166-d7767868dc43"
                remote: "https://github.com/my-company/repo.git"
                traits:
                - "gitBranchDiscovery"
    checkOutTimeout: 600
    pollingPeriod: 120
    purgeOnDeactivation: false
  bundleUpdateTiming:
    automaticReload: true
    automaticRestart: true
    rejectWarnings: false
    reloadAlwaysOnRestart: false
    skipNewVersions: false
  headerLabel:
    text: "Managed by CasC"
  location:
    adminAddress: "Set me up <nobody@nowhere>"
    url: ${oc_url}
  operationsCenterSharedConfiguration:
    enabled: true
cloudBeesCasCServer:
  disableRemoteValidation: false
  visibility: true
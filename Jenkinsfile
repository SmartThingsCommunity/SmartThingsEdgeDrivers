def getEnvName() {
  def branch = "${env.GIT_BRANCH}"
  print branch
  if (branch == "jenkins-refactor") {return "ALPHA"}
  else if (branch == "jenkins-refactor-beta") {return "BETA"}
  else if (branch == "jenkins-refactor-production") {return "PROD"}
}

def getChangedDrivers() {
  def drivers = [].toSet()
  def driver_prefix = "drivers/"
  for (changeLogSet in currentBuild.changeSets) {
    for (entry in changeLogSet.items) {
      for (file in entry.affectedFiles) {
        if (file.path.startsWith(driver_prefix) && !file.path.contains("test")) {
          def short_path = file.path.substring(driver_prefix.length())
          def first_slash = short_path.indexOf('/') + 1
          def driver_name = short_path.substring(first_slash, short_path.indexOf('/', first_slash))
          drivers.add(driver_name)
        }
      }
    }
  }
  return drivers
}

pipeline {
  parameters {
    string(name: "ENVIRONMENT_URL", defaultValue: "")
    string(name: "NODE_LABEL", defaultValue: "production")
    string(name: "ALPHA_CHANNEL_ID", defaultValue: "")
    string(name: "BETA_CHANNEL_ID", defaultValue: "")
    string(name: "PROD_CHANNEL_ID", defaultValue: "")
    string(name: "DRIVERS_OVERRIDE", defaultValue: "")
    booleanParam(name: "DRY_RUN", defaultValue: true)
  }
  agent {
    docker {
      image 'python:3.10'
      label "${params.NODE_LABEL ?: 'production'}"
      args '--entrypoint= -u 0:0'
    }
  }
  environment {
    ENVIRONMENT_URL = "${params.ENVIRONMENT_URL}"
    ALPHA_CHANNEL_ID = "${params.ALPHA_CHANNEL_ID}"
    BETA_CHANNEL_ID = "${params.BETA_CHANNEL_ID}"
    PROD_CHANNEL_ID = "${params.PROD_CHANNEL_ID}"
    TOKEN = credentials("EDGE_DRIVER_DEPLOY_TOKEN_${env.NODE_LABEL.toUpperCase()}")
    BOSE_AUDIONOTIFICATION_APPKEY = credentials("BOSE_AUDIONOTIFICATION_APPKEY")
    SONOS_API_KEY = credentials("SONOS_API_KEY")
    SONOS_OAUTH_API_KEY = credentials("SONOS_OAUTH_API_KEY")
    DRIVERS_OVERRIDE = "${params.DRIVERS_OVERRIDE}"
    DRY_RUN = "${params.DRY_RUN}"
    BRANCH = getEnvName()
    CHANGED_DRIVERS = getChangedDrivers()
    ENVIRONMENT = "${env.NODE_LABEL.toUpperCase()}"
  }
  stages {
    stage('requirements') {
      steps {
        script {
          currentBuild.displayName = "#" + currentBuild.number + " " + env.BRANCH
          currentBuild.description = "Drivers changed: " + env.CHANGED_DRIVERS
        }
        sh 'git config --global --add safe.directory "*"'
        sh 'git clean -xfd'
        sh 'apt-get update'
        sh 'apt-get install zip -y'
        sh 'pip3 install -r tools/requirements.txt'
      }
    }
    stage('update') {
      stages {
        stage('environment_update') {
          steps {
            sh 'python3 tools/deploy.py'
          }
        }
      }
    }
  }
}

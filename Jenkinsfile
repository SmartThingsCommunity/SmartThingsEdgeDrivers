def getEnvName() {
  def branch = "${env.GIT_BRANCH}"
  print branch
  if (branch == "origin/main") {return "ALPHA"}
  else if (branch == "origin/beta") {return "BETA"}
  else if (branch == "origin/production") {return "PROD"}
  else if (branch == "origin/un-migrate-zigbee-locks") {return "TEST"}
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

def get_region() {
  def url = env.JENKINS_URL?.trim()
  if (url?.endsWith('/')) {
    url = url[0..-2]
  }

  def region = url?.endsWith('.cn') ? 'cn' : 'global'
  return region
}

// Gate artifactory-credentials for prod nodes in cn due to a docker authentication error arising in that environment
def getDockerCredentialId() {
    def nodeLabel = params.NODE_LABEL ?: 'production'
    def region = get_region()
    if (nodeLabel == 'production' && region == 'cn') {
      return 'artifactory-credentials'
    }
    else {
      return ''
    }
}
// Gate RegistryUrl for prod nodes in cn due to a docker authentication error arising in that environment
def getRegistryUrl() {
  def nodeLabel = params.NODE_LABEL ?: 'production'
  def region = get_region()
  if (nodeLabel == 'production' && region == 'cn') {
    return 'https://registry.artifactoryedge.streleng.cn'
  } else {
    // Default
    return ''
  }
}

pipeline {
  agent {
    docker {
      image 'python:3.10'
      label  "${params.NODE_LABEL ?: 'production'}"
      registryUrl getRegistryUrl()
      registryCredentialsId getDockerCredentialId()
      args '--entrypoint= -u 0:0'
    }
  }
  environment {
    BRANCH = getEnvName()
    CHANGED_DRIVERS = getChangedDrivers()
    ENVIRONMENT = "${env.NODE_LABEL.toUpperCase()}"
    FAILURE_FILE = "failures.log"
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
            script {
              if (fileExists(env.FAILURE_FILE)) {
                currentBuild.description += readFile(env.FAILURE_FILE)
                currentBuild.result = 'UNSTABLE'
              }
            }
          }
        }
      }
    }
  }
}

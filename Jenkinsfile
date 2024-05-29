def getEnvName() {
  def branch = "${env.GIT_BRANCH}"
  print branch
  if (branch == "origin/main") {return "ALPHA"}
  else if (branch == "origin/beta") {return "BETA"}
  else if (branch == "origin/production") {return "PROD"}
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
  agent {
    docker {
      image 'python:3.10'
      label 'production'
      args '--entrypoint= -u 0:0'
    }
  }
  environment {
    BRANCH = getEnvName()
    CHANGED_DRIVERS = getChangedDrivers()
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
      matrix {
        axes {
          axis {
            name 'ENVIRONMENT'
            values 'DEV', 'STAGING', 'ACCEPTANCE', 'PRODUCTION'
          }
        }
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
}


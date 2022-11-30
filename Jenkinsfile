def getEnvName() {
  def branch = "${env.GIT_BRANCH}"
  print branch
  if (branch == "origin/main") {return "ALPHA"}
  else if (branch == "origin/beta") {return "BETA"}
  else if (branch == "origin/production") {return "PROD"}
}

def getChangedDrivers() {
  def drivers = [].toSet()
  def driver_prefix = "drivers/SmartThings/"
  for (changeLogSet in currentBuild.changeSets) {
    for (entry in changeLogSet.items) {
      for (file in entry.affectedFiles) {
        if (file.path.startsWith(driver_prefix) && !file.path.contains("test")) {
          def short_path = file.path.substring(driver_prefix.length())
          def driver_name = short_path.substring(0, short_path.indexOf('/'))
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
      image 'smartthings-registry.jfrog.io/iot/edge/edblua-formatter:latest'
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
        sh 'git clean -xfd'
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
              script {
                sh 'python3 tools/deploy.py'
              }
            }
          }
        }
      }
    }
  }
}


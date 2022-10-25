def getEnvName() {
  def branch = "${env.GIT_BRANCH}"
  print branch
  if (branch == "origin/main") {return "ALPHA"}
  else if (branch == "origin/beta") {return "BETA"}
  else if (branch == "origin/production") {return "PROD"}
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


def getEnvName(branch) {
  print(branch)
  if (branch == "origin/main") {return "ALPHA"}
  if (branch == "origin/beta") {return "BETA"}
  if (branch == "origin/production") {return "PRODUCTION"}
}

pipeline {
  agent {
    docker {
      image 'smartthings-registry.jfrog.io/iot/edge/edblua-formatter:latest'
      label 'production'
      args '--entrypoint='
    }
  }
  stages {
    stage('update') {
      steps {
        script {
          // ugly hacks to get branch name and correct env variables for that branch
          branchName = sh(returnStdout: true, script: 'echo $GIT_BRANCH').trim()
          env_name = getEnvName(branchName)
          env.ENVIRONMENT_URL = sh(returnStdout: true, script: "echo \$${env_name+'_ENVIRONMENT_URL'}").trim()
          env.CHANNEL_ID = sh(returnStdout: true, script: "echo \$${env_name+'_CHANNEL_ID'}").trim()
          env.TOKEN = sh(returnStdout: true, script: "echo \$${env_name+'_TOKEN'}").trim()
        }
        sh 'pip3 install -r ./tools/requirements.txt'
        sh 'python3 ./tools/deploy.py'
      }
    }
  }
}



//////////////////////FASE 1


# Set up Dev Project
oc new-project ${GUID}-tasks-dev --display-name "${GUID} Tasks Development"

oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-tasks-dev

# Set up Dev Application
oc new-build --binary=true --name="tasks" jboss-eap71-openshift:1.4 -n ${GUID}-tasks-dev

oc new-app ${GUID}-tasks-dev/tasks:0.0-0 --name=tasks --allow-missing-imagestream-tags=true -n ${GUID}-tasks-dev

oc set triggers dc/tasks --remove-all -n ${GUID}-tasks-devoc expose dc tasks --port 8080 -n ${GUID}-tasks-dev
oc expose svc tasks -n ${GUID}-tasks-dev

oc set probe dc/tasks -n ${GUID}-tasks-dev --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/

oc create configmap tasks-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" -n ${GUID}-tasks-dev

oc set volume dc/tasks --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=tasks-config -n ${GUID}-tasks-devoc set volume dc/tasks --add --name=jboss-config1 --mount-
path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=tasks-config -n ${GUID}-tasks-dev





//////////////////////FASE 2


# Set up Production Project

oc new-project ${GUID}-tasks-prod --display-name "${GUID} Tasks Production"
oc policy add-role-to-group system:image-puller system:serviceaccounts:${GUID}-tasks-prod -n ${GUID}-tasks-dev

oc policy add-role-to-user edit system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-tasks-prod

# Create Blue Application

oc new-app ${GUID}-tasks-dev/tasks:0.0 --name=tasks-blue --allow-missing-imagestream-tags=true -n ${GUID}-tasks-prod

//no
oc set triggers dc/tasks-blue --remove-all -n ${GUID}-tasks-prod
oc expose dc tasks-blue --port 8080 -n ${GUID}-tasks-prod

oc set probe dc tasks-blue -n ${GUID}-tasks-prod --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/

oc create configmap tasks-blue-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" -n ${GUID}-tasks-prod

#no oc set volume dc/tasks-blue --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=tasks-blue-config -n ${GUID}-tasks-prod

#no oc set volume dc/tasks-blue --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=tasks-blue-config -n ${GUID}-tasks-prod

# Create Green Application

oc new-app ${GUID}-tasks-dev/tasks:0.0 --name=tasks-green --allow-missing-imagestream-tags=true -n ${GUID}-tasks-prod

oc set triggers dc/tasks-green --remove-all -n ${GUID}-tasks-prod
oc expose dc tasks-green --port 8080 -n ${GUID}-tasks-prod

oc set probe dc tasks-green -n ${GUID}-tasks-prod --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/

oc create configmap tasks-green-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" -n ${GUID}-tasks-prod

#no oc set volume dc/tasks-green --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=tasks-green-config -n ${GUID}-tasks-prod

#no oc set volume dc/tasks-green --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=tasks-green-config -n ${GUID}-tasks-prod


# Expose Blue service as route to make blue application active
oc expose svc/tasks-blue --name tasks -n ${GUID}-tasks-prod



//////////////////////FASE 3 - CONSTRUIR PIPELINE


// Set your project Prefix using your GUID
def prefix = "GUID"
// Set variable globally to be available in all stages
// Set Maven command to always include Nexus Settings
def mvnCmd = "mvn -s ./nexus_openshift_settings.xml"
// Set Development and Production Project Names
def devProject = "${prefix}-tasks-dev"
def prodProject = "${prefix}-tasks-prod"
// Set the tag for the development image: version + build number
def devTag = "0.0-0"
// Set the tag for the production image: version
def prodTag = "0.0"
def destApp = "tasks-green"
def activeApp = ""


pipeline {
 agent {
  // Using the Jenkins Agent Pod that we defined earlier

  label "maven-appdev"
 }
 stages {


  stage('Checkout Source') {
   steps {
    // Replace the credentials with your credentials.
    git credentialsId: '5a9e972e-6bf7-46a3-a37f-1f7aaffeefa8', url: "http://gogs.${prefix}-gogs.svc.cluster.local: 3000/CICDLabs/openshift-tasks-private.git"
    // or when using the Pipeline from the repo itself:
    // checkout scm
    script {
     def pom = readMavenPom file: 'pom.xml'
     def version = pom.version
     // Set the tag for the development image: version + build number
     devTag = "${version}-" + currentBuild.number
     // Set the tag for the production image: version
     prodTag = "${version}"
    }
   }
  }


  // Using Maven build the war file
  // Do not run tests in this step
  stage('Build App') {
   steps {
    echo "Building version ${devTag}"
    sh "${mvnCmd} clean package -DskipTests=true"
   }
  }

  // Using Maven run the unit tests
  stage('Unit Tests') {
   steps {
    echo "Running Unit Tests"
    sh "${mvnCmd} test"
    // This next step is optional.
    // It displays the results of tests in the Jenkins Task Overview

    step([$class: 'JUnitResultArchiver', testResults: '**/target/surefire-reports/TEST-*.xml'])
   }
  }

  // Using Maven call SonarQube for Code Analysis
  stage('Code Analysis') {
   steps {
    script {
     echo "Running Code Analysis"
     sh "${mvnCmd} sonar:sonar -Dsonar.host.url=http://sonarqube-${prefix}-sonarqube.apps.fab.example.opentlc.com/ -Dsonar.projectName = ${JOB_BASE_NAME}-Dsonar.projectVersion = ${devTag}"
    }
   }
  }


  // Publish the built war file to Nexus
  stage('Publish to Nexus') {
   steps {
    echo "Publish to Nexus"
    sh "${mvnCmd} deploy -DskipTests=true -DaltDeploymentRepository=nexus::default::http://nexus3.${prefix}-nexus.svc.cluster.local: 8081/repository/releases"
   }
  }


  // Build the OpenShift Image in OpenShift and tag it.
  stage('Build and Tag OpenShift Image') {
   steps {
    echo "Building OpenShift container image tasks:${devTag}"
    // Start Binary Build in OpenShift using the file we just published
    // The filename is openshift-tasks.war in the 'target' directory of your current
    // Jenkins workspace
    script {
     openshift.withCluster() {
      openshift.withProject("${devProject}") {
       openshift.selector("bc", "tasks").startBuild("--from-file=./target/openshift-tasks.war","--wait=true")

        // OR use the file you just published into Nexus:
        // "--from-file=http://nexus3.${prefix}-nexus.svc.cluster.local:8081/repository/releases/org/jboss/quickstarts/eap/tasks/${version}/tasks-${version}.war "openshift.tag("tasks:latest", "tasks:${devTag}")
       }
      }
     }
    }
   }





   // Deploy the built image to the Development Environment.
   stage('Deploy to Dev') {
    steps {
     echo "Deploying container image to Development Project"

     script {

      // Update the Image on the Development Deployment Config
      openshift.withCluster() {

       openshift.withProject("${devProject}") {
        // OpenShift 4

        openshift.set("image", "dc/tasks", "tasks=image-registry.openshift-image-registry.svc:5000/${devProject}/tasks:${devTag}")

        // For OpenShift 3 use this:

        // openshift.set("image", "dc/tasks", "tasks=docker-registry.default.svc 5000/${devProject}/tasks:${devTag}")

        // Update the Config Map which contains the users for the Tasks application
        // (just in case the properties files changed in the latest commit)
        openshift.selector('configmap', 'tasks-config').delete()

        def configmap = openshift.create('configmap', 'tasks-config', '--from-file=./configuration/application-users.properties', '--from-file=./configuration/application-roles.properties')

        // Deploy the development application.
        openshift.selector("dc", "tasks").rollout().latest();

        // Wait for application to be deployed
        def dc = openshift.selector("dc", "tasks").object()
        def dc_version = dc.status.latestVersion
        def rc = openshift.selector("rc", "tasks-${dc_version}").object()

        echo "Waiting for ReplicationController tasks-${dc_version} to be ready"

        while (rc.spec.replicas != rc.status.readyReplicas) {
         sleep 5
         rc = openshift.selector("rc", "tasks-${dc_version}").object()
        }

       } //withProject
      } //withCluster
     } //script
    }
   } //stage


   // Blue/Green Deployment into Production
   // -------------------------------------
   // Do not activate the new version yet.
   stage('Blue/Green Production Deployment') {
    steps {
     echo "Blue/Green Deployment"
     script {
      openshift.withCluster() {
       openshift.withProject("${prodProject}") {
        activeApp = openshift.selector("route", "tasks").object().spec.to.name
        if (activeApp == "tasks-green") {
         destApp = "tasks-blue"

        }
        echo "Active Application: " + activeApp
        echo "Destination Application: " + destApp
        // Update the Image on the Production Deployment Config
        def dc = openshift.selector("dc/${destApp}").object()
        // OpenShift 4

        dc.spec.template.spec.containers[0].image = "image-registry.openshift-image-registry.svc:5000/${devProject}/tasks:${prodTag}"

        // OpenShift 3

        // dc.spec.template.spec.containers[0].image="docker-registry.default.svc:5000 / ${devProject}/tasks:${prodTag}"

        openshift.apply(dc)
        // Update Config Map in change config files changed in the source
        openshift.selector("configmap", "${destApp}-config").delete()

        def configmap = openshift.create("configmap", "${destApp}-config", "--from-file =./configuration/application-users.properties", "--from-file =./configuration/application-roles.properties")

        // Deploy the inactive application.
        openshift.selector("dc", "${destApp}").rollout().latest();
        
		// Wait for application to be deployed
        def dc_prod = openshift.selector("dc", "${destApp}").object() 
		def dc_version = dc_prod.status.latestVersion 
		def rc_prod = openshift.selector("rc", "${destApp}-${dc_version}").object() echo "Waiting for ${destApp} to be ready"
		
        while (rc_prod.spec.replicas != rc_prod.status.readyReplicas) {
         sleep 5
         rc_prod = openshift.selector("rc", "${destApp}-${dc_version}").object()
        }
       }
      }
     }
    }
   }
  }

  stage('Switch over to new Version') {
   steps {
    input "Switch Production?"
    echo "Switching Production application to ${destApp}."
    script {
     openshift.withCluster() {
      openshift.withProject("${prodProject}") {
       def route = openshift.selector("route/tasks").object()
       route.spec.to.name = "${destApp}"
       openshift.apply(route)
      }
     }
    }
   }
  }


 } //stage
} //pipeline



              stage('Deploy STAGE') {
                steps {
                  script {
                    openshift.withCluster() {

                      openshift.withProject(env.STAGE_PROJECT) {
                        // Update the Config Map which contains the users for the Tasks application
                        openshift.selector('configmap', 'tasks-config').delete()
                        // Update the Config Map which contains the users for the Tasks application         
                        def configmap = openshift.create('configmap', 'tasks-config', '--from-file=./configuration/application-users.properties', '--from-file=./configuration/application-roles.properties')
                        // Deploy the development application.
                        openshift.selector("dc", "tasks").rollout().latest();

                        // Wait for application to be deployed
                        def dc = openshift.selector("dc", "tasks").object() 
                        def dc_version = dc.status.latestVersion 
                        def rc = openshift.selector("rc", "tasks-${dc_version}").object() 

                        echo "Waiting for ReplicationController tasks-${dc_version} to be ready"

                        while (rc.spec.replicas != rc.status.readyReplicas) {
                            sleep 5
                            rc = openshift.selector("rc", "tasks-${dc_version}").object()
                        }  
                      }
                    }
                  }
                }
              }


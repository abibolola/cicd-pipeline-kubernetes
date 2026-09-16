pipeline {
    agent any

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    environment {
        // ---- EDIT THIS ONE ----
        DOCKERHUB_USER = 'YOUR_DOCKERHUB_USERNAME'

        IMAGE_REPO   = "${DOCKERHUB_USER}/shortener"
        RG           = 'rg-shortener'
        CLUSTER      = 'aks-shortener'
        NS           = 'shortener'

        // Per-build kubeconfig so concurrent builds can never clobber
        // each other, and no long-lived cluster credential sits on disk.
        KUBECONFIG   = "${WORKSPACE}/.kube-${BUILD_NUMBER}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    // Short SHA is the image tag. Immutable, traceable,
                    // and it forces Kubernetes to notice the pod template changed.
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.IMAGE = "${IMAGE_REPO}:${env.GIT_SHA}"
                    currentBuild.displayName = "#${BUILD_NUMBER} ${env.GIT_SHA}"
                }
                echo "Building ${env.IMAGE}"
            }
        }

        stage('Lint & Test') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    reuseNode true
                    args '-u root'
                }
            }
            steps {
                sh '''
                    pip install --no-cache-dir -q -r requirements-dev.txt
                    ruff check .
                    pytest -q --junitxml=test-results.xml
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'test-results.xml'
                }
            }
        }

        stage('Build Image') {
            steps {
                sh """
                    docker build \
                      --build-arg APP_VERSION=${env.GIT_SHA} \
                      -t ${env.IMAGE} .
                """
            }
        }

        stage('Scan Image') {
            steps {
                // Non-blocking for now: report findings without failing the build.
                // Switch --exit-code to 1 once the baseline is clean.
                sh """
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --exit-code 0 \
                      ${env.IMAGE}
                """
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub',
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_PASS'
                )]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker push ''' + "${env.IMAGE}" + '''
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to AKS') {
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'azure-sp',
                                     usernameVariable: 'AZ_APP_ID',
                                     passwordVariable: 'AZ_PASSWORD'),
                    string(credentialsId: 'azure-tenant', variable: 'AZ_TENANT'),
                    string(credentialsId: 'redis-password', variable: 'REDIS_PASSWORD')
                ]) {
                    sh '''
                        set -e

                        az login --service-principal \
                          -u "$AZ_APP_ID" -p "$AZ_PASSWORD" -t "$AZ_TENANT" > /dev/null

                        # Fresh kubeconfig every build. The cluster is recreated
                        # between sessions, so a stored one would go stale.
                        az aks get-credentials \
                          --resource-group "$RG" --name "$CLUSTER" \
                          --overwrite-existing

                        kubectl apply -f k8s/00-namespace.yaml

                        # Idempotent secret: create|apply works whether or not it exists.
                        kubectl create secret generic shortener-secrets \
                          --namespace "$NS" \
                          --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
                          --dry-run=client -o yaml | kubectl apply -f -

                        kubectl apply -f k8s/01-configmap.yaml
                        kubectl apply -f k8s/03-redis-service.yaml
                        kubectl apply -f k8s/04-redis-statefulset.yaml
                        kubectl apply -f k8s/06-app-service.yaml
                        kubectl apply -f k8s/07-pdb.yaml

                        kubectl -n "$NS" rollout status statefulset/redis --timeout=180s
                    '''

                    // The LoadBalancer IP only exists after Azure provisions it,
                    // so BASE_URL cannot be known until this point.
                    sh '''
                        set -e
                        echo "Waiting for LoadBalancer IP..."
                        for i in $(seq 1 60); do
                          IP=$(kubectl -n "$NS" get svc shortener \
                               -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
                          [ -n "$IP" ] && break
                          sleep 5
                        done
                        [ -n "$IP" ] || { echo "No LoadBalancer IP after 5m"; exit 1; }
                        echo "LB_IP=$IP" > lb.env
                        echo "External IP: $IP"

                        kubectl -n "$NS" patch configmap shortener-config \
                          --type merge -p "{\\"data\\":{\\"BASE_URL\\":\\"http://$IP\\"}}"
                    '''

                    sh '''
                        set -e
                        sed "s|IMAGE_PLACEHOLDER|''' + "${env.IMAGE}" + '''|" \
                          k8s/05-app-deployment.yaml | kubectl apply -f -

                        # The gate. Fails the build if pods never become Ready.
                        kubectl -n "$NS" rollout status deployment/shortener --timeout=180s
                        kubectl -n "$NS" get pods -o wide
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -e
                    . ./lb.env

                    echo "--- health ---"
                    curl -fsS --retry 10 --retry-delay 3 --retry-connrefused \
                      "http://$LB_IP/healthz"
                    echo

                    echo "--- create ---"
                    CODE=$(curl -fsS -X POST "http://$LB_IP/shorten" \
                      -H 'content-type: application/json' \
                      -d '{"url":"https://kubernetes.io/docs"}' \
                      | sed -n 's/.*"code":"\\([^"]*\\)".*/\\1/p')
                    [ -n "$CODE" ] || { echo "No code returned"; exit 1; }
                    echo "code=$CODE"

                    echo "--- follow ---"
                    STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://$LB_IP/$CODE")
                    [ "$STATUS" = "307" ] || { echo "Expected 307, got $STATUS"; exit 1; }
                    echo "Smoke test passed."
                '''
            }
        }
    }

    post {
        failure {
            // Only meaningful if a previous good revision exists.
            sh '''
                if kubectl -n "$NS" rollout history deployment/shortener >/dev/null 2>&1; then
                  echo "Rolling back..."
                  kubectl -n "$NS" rollout undo deployment/shortener || true
                  kubectl -n "$NS" rollout status deployment/shortener --timeout=120s || true
                fi
            '''
        }
        always {
            sh '''
                rm -f "$KUBECONFIG" lb.env || true
                docker image prune -f --filter "until=24h" || true
                az logout 2>/dev/null || true
            '''
        }
    }
}
